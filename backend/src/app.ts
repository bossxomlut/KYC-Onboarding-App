import Fastify from "fastify";
import multipart from "@fastify/multipart";
import rateLimit from "@fastify/rate-limit";
import { ZodError } from "zod";
import type { Pool } from "pg";
import type { Config } from "./config.js";
import type { Mailer } from "./mail.js";
import { createMailer, startOutboxWorker } from "./mail.js";
import { ApiError } from "./errors.js";
import { registerAuth } from "./auth.js";
import { registerKyc } from "./kyc.js";

export async function buildApp(
  config: Config,
  pool: Pool,
  mailer: Mailer = createMailer(config),
) {
  const app = Fastify({
    logger: false,
    bodyLimit: 16384,
    requestTimeout: 30000,
    connectionTimeout: 10000,
    trustProxy: false,
  });
  await app.register(multipart, {
    limits: { fileSize: config.maxUploadBytes, files: 1, fields: 2, parts: 3 },
  });
  // Per-IP limits prevent changing email addresses from bypassing limits.
  // OTP also has durable per-code attempt limits and a per-user resend cooldown.
  await app.register(rateLimit, {
    global: true,
    max: 120,
    timeWindow: "1 minute",
    errorResponseBuilder() {
      return new ApiError(
        429,
        "RATE_LIMITED",
        "Too many attempts. Please try again shortly.",
      );
    },
  });
  app.addHook("onSend", async (_request, reply, payload) => {
    reply
      .header("cache-control", "no-store")
      .header("x-content-type-options", "nosniff")
      .header("referrer-policy", "no-referrer");
    return payload;
  });
  app.setErrorHandler((error, request, reply) => {
    let status = 500;
    let code = "INTERNAL_ERROR";
    let message = "Unable to complete the request. Please try again.";
    if (error instanceof ApiError) {
      status = error.status;
      code = error.code;
      message = error.message;
    } else if (error instanceof ZodError) {
      status = 400;
      code = "VALIDATION_ERROR";
      message = error.issues
        .map(
          (issue) => `${issue.path.join(".") || "request"}: ${issue.message}`,
        )
        .join("; ");
    } else if ((error as { statusCode?: number }).statusCode === 429) {
      status = 429;
      code = "RATE_LIMITED";
      message = "Too many attempts. Please try again shortly.";
    } else if (
      (error as { code?: string }).code === "FST_REQ_FILE_TOO_LARGE" ||
      (error as { code?: string }).code === "FST_FILES_LIMIT"
    ) {
      status = 413;
      code = "UPLOAD_TOO_LARGE";
      message = `Upload one image smaller than ${config.maxUploadBytes / 1024 / 1024} MB.`;
    } else if ((error as { statusCode?: number }).statusCode === 413) {
      status = 413;
      code = "REQUEST_TOO_LARGE";
      message = "The request is too large.";
    } else if (
      (error as { statusCode?: number }).statusCode === 400 ||
      (error as { statusCode?: number }).statusCode === 415
    ) {
      status = 400;
      code = "INVALID_REQUEST";
      message = "The request format is invalid.";
    }
    reply
      .status(status)
      .send({ error: { code, message, requestId: request.id } });
  });
  app.setNotFoundHandler((request, reply) =>
    reply.code(404).send({
      error: {
        code: "NOT_FOUND",
        message: "Endpoint not found.",
        requestId: request.id,
      },
    }),
  );
  app.get("/health", async () => {
    await pool.query("SELECT 1");
    return { status: "ok" };
  });
  await registerAuth(app, pool, config, mailer);
  registerKyc(app, pool, config);
  if (config.nodeEnv !== "test") {
    const stop = startOutboxWorker(pool, config, mailer);
    app.addHook("onClose", async () => {
      stop();
    });
  }
  return app;
}
