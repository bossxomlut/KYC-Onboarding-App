import "reflect-metadata";
import { NestFactory } from "@nestjs/core";
import {
  ExpressAdapter,
  type NestExpressApplication,
} from "@nestjs/platform-express";
import express from "express";
import { randomUUID } from "node:crypto";
import type { Pool } from "pg";
import type { Server } from "node:http";
import type { Config } from "./config.js";
import { createMailer, type Mailer } from "./mail.js";
import { AppModule } from "./app.module.js";

export async function buildApp(
  config: Config,
  pool: Pool,
  mailer: Mailer = createMailer(config),
): Promise<NestExpressApplication> {
  const adapter = new ExpressAdapter();
  adapter.getInstance().disable("x-powered-by");
  adapter.getInstance().disable("etag");
  adapter.getInstance().set("trust proxy", false);
  const app = await NestFactory.create<NestExpressApplication>(
    AppModule.register(config, pool, mailer),
    adapter,
    {
      logger: false,
      bodyParser: false,
      abortOnError: false,
    },
  );
  app.use(
    (
      request: express.Request & { requestId?: string },
      response: express.Response,
      next: express.NextFunction,
    ) => {
      request.requestId = randomUUID();
      response.setHeader("cache-control", "no-store");
      response.setHeader("x-content-type-options", "nosniff");
      response.setHeader("referrer-policy", "no-referrer");
      response.setHeader("x-request-id", request.requestId);
      next();
    },
  );
  app.use(express.json({ limit: "16kb" }));
  app.use(express.urlencoded({ extended: false, limit: "16kb" }));
  const server: Server = app.getHttpServer();
  server.requestTimeout = 30000;
  server.headersTimeout = 30000;
  server.timeout = 10000;
  await app.init();
  return app;
}
