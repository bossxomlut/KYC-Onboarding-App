import { randomUUID } from "node:crypto";
import { mkdir, readFile, writeFile, rm } from "node:fs/promises";
import { join } from "node:path";
import type { Pool, PoolClient } from "pg";
import type { FastifyInstance } from "fastify";
import sharp from "sharp";
import { z } from "zod";
import { ApiError } from "./errors.js";
import type { Config } from "./config.js";
import { authentication } from "./auth.js";
import { transaction } from "./database.js";
import { decrypt, encrypt } from "./security.js";

export const requiredStepSchema = z.enum([
  "personal_details",
  "document",
  "selfie",
]);
const documentTypeSchema = z.enum([
  "passport",
  "national_id",
  "driving_licence",
]);
const kindSchema = z.enum(["document", "selfie"]);
const personalSchema = z.strictObject({
  fullName: z.string().trim().min(2).max(120),
  dateOfBirth: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/)
    .refine(
      (value) => {
        const birthday = new Date(`${value}T00:00:00Z`);
        if (
          Number.isNaN(birthday.getTime()) ||
          birthday.toISOString().slice(0, 10) !== value
        )
          return false;
        const today = new Date();
        const years =
          today.getUTCFullYear() -
          birthday.getUTCFullYear() -
          (today.getUTCMonth() < birthday.getUTCMonth() ||
          (today.getUTCMonth() === birthday.getUTCMonth() &&
            today.getUTCDate() < birthday.getUTCDate())
            ? 1
            : 0);
        return years >= 18 && years <= 120;
      },
      { message: "Enter a valid birth date. Applicants must be 18 or older." },
    ),
  nationality: z.string().trim().min(2).max(80),
  address: z.string().trim().min(8).max(500),
  documentNumber: z
    .string()
    .trim()
    .min(4)
    .max(40)
    .regex(/^[A-Za-z0-9 -]+$/),
});

function editable(profile: any) {
  if (!["not_started", "in_progress"].includes(profile.status))
    throw new ApiError(
      409,
      "KYC_LOCKED",
      "This profile cannot be edited in its current status. Rejected profiles must be reopened first.",
    );
}
async function lockedProfile(client: PoolClient, userId: string) {
  const result = await client.query(
    "SELECT * FROM kyc_profiles WHERE user_id=$1 FOR UPDATE",
    [userId],
  );
  if (!result.rowCount)
    throw new ApiError(404, "KYC_NOT_FOUND", "Profile not found.");
  return result.rows[0];
}
const meta = (row: any) =>
  row
    ? {
        id: row.id,
        mimeType: row.mime_type,
        size: row.size,
        ...(row.client_capture_id ? { captureId: row.client_capture_id } : {}),
        ...(row.kind === "document" ? { documentType: row.document_type } : {}),
      }
    : null;
export async function getProfile(
  client: Pool | PoolClient,
  userId: string,
  config: Config,
) {
  const profiles = await client.query(
    "SELECT * FROM kyc_profiles WHERE user_id=$1",
    [userId],
  );
  const row = profiles.rows[0];
  if (!row) throw new ApiError(404, "KYC_NOT_FOUND", "Profile not found.");
  const records = await client.query(
    "SELECT * FROM kyc_media WHERE user_id=$1",
    [userId],
  );
  const document = meta(records.rows.find((item) => item.kind === "document"));
  const selfie = meta(records.rows.find((item) => item.kind === "selfie"));
  const personalDetails = row.personal_details
    ? JSON.parse(
        decrypt(
          Buffer.from(row.personal_details, "base64"),
          config.mediaKey,
        ).toString("utf8"),
      )
    : null;
  const nextStep = ["pending_review", "verified", "rejected"].includes(
    row.status,
  )
    ? "result"
    : !personalDetails
      ? "personal_details"
      : !document
        ? "document"
        : !selfie
          ? "selfie"
          : "review";
  return {
    id: row.id,
    status: row.status,
    nextStep,
    personalDetails,
    document,
    selfie,
    rejectionReason: row.rejection_reason,
    requiredSteps: row.required_steps,
    submittedAt: row.submitted_at?.toISOString() ?? null,
    updatedAt: row.updated_at.toISOString(),
  };
}

export async function reviewProfile(
  pool: Pool,
  userId: string,
  status: "verified" | "rejected",
  reason?: string,
  requiredSteps: string[] = [],
) {
  if (status === "rejected" && (!reason?.trim() || requiredSteps.length === 0))
    throw new ApiError(
      400,
      "INVALID_REVIEW",
      "A rejection requires a reason and at least one required step.",
    );
  const steps = z.array(requiredStepSchema).max(3).parse(requiredSteps);
  await transaction(pool, async (client) => {
    const profile = await lockedProfile(client, userId);
    if (profile.status !== "pending_review")
      throw new ApiError(
        409,
        "KYC_REVIEW_NOT_PENDING",
        "Only pending profiles can be reviewed.",
      );
    await client.query(
      "UPDATE kyc_profiles SET status=$2,rejection_reason=$3,required_steps=$4,updated_at=now() WHERE user_id=$1",
      [
        userId,
        status,
        status === "rejected" ? reason!.trim() : null,
        status === "rejected" ? [...new Set(steps)] : [],
      ],
    );
    await client.query(
      "INSERT INTO kyc_reviews(id,user_id,decision,required_steps) VALUES($1,$2,$3,$4)",
      [randomUUID(), userId, status, status === "rejected" ? steps : []],
    );
  });
}

export function registerKyc(app: FastifyInstance, pool: Pool, config: Config) {
  const protectedRoute = { preHandler: authentication(pool, config) };
  app.get("/api/v1/kyc", protectedRoute, async (request) => ({
    profile: await getProfile(pool, request.userId, config),
  }));
  app.put("/api/v1/kyc/personal-details", protectedRoute, async (request) => {
    const details = personalSchema.parse(request.body);
    return transaction(pool, async (client) => {
      editable(await lockedProfile(client, request.userId));
      const encrypted = encrypt(
        Buffer.from(JSON.stringify(details)),
        config.mediaKey,
      ).toString("base64");
      await client.query(
        "UPDATE kyc_profiles SET personal_details=$2,status='in_progress',updated_at=now() WHERE user_id=$1",
        [request.userId, encrypted],
      );
      return { profile: await getProfile(client, request.userId, config) };
    });
  });
  app.post("/api/v1/kyc/media/:kind", protectedRoute, async (request) => {
    const { kind } = z.object({ kind: kindSchema }).parse(request.params);
    // Check status before buffering/decoding expensive image data, then recheck while locked.
    const current = await pool.query(
      "SELECT status FROM kyc_profiles WHERE user_id=$1",
      [request.userId],
    );
    editable(current.rows[0]);
    let image: Buffer | undefined;
    let documentType: unknown;
    let rawCaptureId: unknown;
    let declaredType: string | undefined;
    for await (const part of request.parts()) {
      if (part.type === "file") {
        if (part.fieldname !== "file" || image) {
          await part.toBuffer();
          throw new ApiError(
            400,
            "INVALID_UPLOAD",
            "Upload one image using the file field.",
          );
        }
        image = await part.toBuffer();
        declaredType = part.mimetype;
      } else if (part.fieldname === "documentType") documentType = part.value;
      else if (part.fieldname === "captureId") rawCaptureId = part.value;
      else
        throw new ApiError(
          400,
          "INVALID_UPLOAD",
          "Unexpected multipart field.",
        );
    }
    if (!image || image.length === 0)
      throw new ApiError(400, "INVALID_UPLOAD", "Choose a JPEG or PNG image.");
    const captureId = z
      .string()
      .min(16)
      .max(128)
      .regex(/^[A-Za-z0-9_-]+$/)
      .optional()
      .parse(rawCaptureId);
    const validJpeg =
      image.length >= 3 &&
      image[0] === 0xff &&
      image[1] === 0xd8 &&
      image[2] === 0xff;
    const validPng =
      image.length >= 8 &&
      image
        .subarray(0, 8)
        .equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
    if (
      (!validJpeg && !validPng) ||
      !["image/jpeg", "image/png"].includes(declaredType ?? "")
    )
      throw new ApiError(
        400,
        "INVALID_UPLOAD",
        "Only valid JPEG and PNG images are accepted.",
      );
    let sanitized: Buffer;
    try {
      // Decode and re-encode to remove EXIF/GPS and ensure content is a real image.
      sanitized = await sharp(image, {
        limitInputPixels: 20_000_000,
        failOn: "warning",
      })
        .rotate()
        .jpeg({ quality: 90 })
        .toBuffer();
    } catch {
      throw new ApiError(
        400,
        "INVALID_UPLOAD",
        "The image is corrupt or too large to process. Choose a different image.",
      );
    }
    const type =
      kind === "document" ? documentTypeSchema.parse(documentType) : null;
    const key = randomUUID();
    const location = join(config.mediaDir, key);
    await mkdir(config.mediaDir, { recursive: true, mode: 0o700 });
    await writeFile(location, encrypt(sanitized, config.mediaKey), {
      mode: 0o600,
      flag: "wx",
    });
    let oldKey: string | undefined;
    let existingCapture = false;
    try {
      const result = await transaction(pool, async (client) => {
        editable(await lockedProfile(client, request.userId));
        const old = await client.query(
          "SELECT storage_key,client_capture_id FROM kyc_media WHERE user_id=$1 AND kind=$2",
          [request.userId, kind],
        );
        if (captureId && old.rows[0]?.client_capture_id === captureId) {
          existingCapture = true;
          return { profile: await getProfile(client, request.userId, config) };
        }
        oldKey = old.rows[0]?.storage_key;
        await client.query(
          "INSERT INTO kyc_media(id,user_id,kind,document_type,mime_type,size,storage_key,client_capture_id) VALUES($1,$2,$3,$4,$5,$6,$7,$8) ON CONFLICT(user_id,kind) DO UPDATE SET id=EXCLUDED.id,document_type=EXCLUDED.document_type,mime_type=EXCLUDED.mime_type,size=EXCLUDED.size,storage_key=EXCLUDED.storage_key,client_capture_id=EXCLUDED.client_capture_id,created_at=now()",
          [
            randomUUID(),
            request.userId,
            kind,
            type,
            "image/jpeg",
            sanitized.length,
            key,
            captureId ?? null,
          ],
        );
        await client.query(
          "UPDATE kyc_profiles SET status='in_progress',updated_at=now() WHERE user_id=$1",
          [request.userId],
        );
        return { profile: await getProfile(client, request.userId, config) };
      });
      if (existingCapture) await rm(location, { force: true }).catch(() => {});
      if (oldKey)
        await rm(join(config.mediaDir, oldKey), { force: true }).catch(
          () => {},
        );
      return result;
    } catch (error) {
      await rm(location, { force: true });
      throw error;
    }
  });
  app.get("/api/v1/kyc/media/:kind", protectedRoute, async (request, reply) => {
    const { kind } = z.object({ kind: kindSchema }).parse(request.params);
    const result = await pool.query(
      "SELECT * FROM kyc_media WHERE user_id=$1 AND kind=$2",
      [request.userId, kind],
    );
    const media = result.rows[0];
    if (!media) throw new ApiError(404, "MEDIA_NOT_FOUND", "Image not found.");
    const data = decrypt(
      await readFile(join(config.mediaDir, media.storage_key)),
      config.mediaKey,
    );
    return reply
      .header("cache-control", "no-store")
      .header("content-disposition", "inline")
      .type(media.mime_type)
      .send(data);
  });
  app.post("/api/v1/kyc/submit", protectedRoute, async (request) =>
    transaction(pool, async (client) => {
      const profile = await lockedProfile(client, request.userId);
      if (profile.status === "pending_review")
        return { profile: await getProfile(client, request.userId, config) };
      editable(profile);
      const media = await client.query(
        "SELECT kind FROM kyc_media WHERE user_id=$1",
        [request.userId],
      );
      if (!profile.personal_details || media.rowCount !== 2)
        throw new ApiError(
          400,
          "KYC_INCOMPLETE",
          "Complete personal details, document and selfie before submitting.",
        );
      await client.query(
        "UPDATE kyc_profiles SET status='pending_review',submitted_at=now(),required_steps='{}',rejection_reason=NULL,updated_at=now() WHERE user_id=$1",
        [request.userId],
      );
      return { profile: await getProfile(client, request.userId, config) };
    }),
  );
  app.post("/api/v1/kyc/resubmit", protectedRoute, async (request) => {
    let oldKeys: string[] = [];
    const result = await transaction(pool, async (client) => {
      const profile = await lockedProfile(client, request.userId);
      if (profile.status !== "rejected")
        throw new ApiError(
          409,
          "KYC_NOT_REJECTED",
          "Only a rejected profile can be reopened.",
        );
      const steps = profile.required_steps as string[];
      const removed = await client.query(
        "DELETE FROM kyc_media WHERE user_id=$1 AND kind=ANY($2::text[]) RETURNING storage_key",
        [request.userId, steps],
      );
      oldKeys = removed.rows.map((item) => item.storage_key);
      await client.query(
        "UPDATE kyc_profiles SET status='in_progress',personal_details=CASE WHEN $2 THEN NULL ELSE personal_details END,rejection_reason=NULL,required_steps='{}',submitted_at=NULL,updated_at=now() WHERE user_id=$1",
        [request.userId, steps.includes("personal_details")],
      );
      return { profile: await getProfile(client, request.userId, config) };
    });
    await Promise.all(
      oldKeys.map((key) =>
        rm(join(config.mediaDir, key), { force: true }).catch(() => {}),
      ),
    );
    return result;
  });
}
