import { Inject, Injectable, Optional } from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import type { Pool } from "pg";
import sharp from "sharp";
import type { Config } from "../config.js";
import { transaction } from "../database.js";
import { ApiError } from "../errors.js";
import {
  APP_CONFIG,
  DATABASE_POOL,
  IDENTITY_VERIFIER,
} from "../infrastructure/tokens.js";
import type { IdentityVerifier } from "../verification/identity-verifier.js";
import { createIdentityVerifier } from "../verification/aws-identity-verifier.js";
import { verifyProfile } from "./kyc-verification.service.js";
import { verificationInProgress } from "./kyc-verification.repository.js";
import { decrypt, encrypt } from "../security.js";
import {
  archivedMedia,
  ensureCurrentSubmission,
  removeUnreferencedMedia,
  submissionHistory,
} from "./kyc-history.repository.js";
import type { HistoryPagination } from "./kyc-history.schemas.js";
import {
  assertEditable,
  getProfile,
  lockedProfile,
  type MediaRecord,
  type ProfileRecord,
} from "./kyc.repository.js";
import {
  documentTypeSchema,
  type MediaKind,
  type PersonalDetails,
  type UploadFields,
} from "./kyc.schemas.js";

export interface UploadedImage {
  data: Buffer;
  mimeType: string;
}

@Injectable()
export class KycService {
  constructor(
    @Inject(DATABASE_POOL) private readonly pool: Pool,
    @Inject(APP_CONFIG) private readonly config: Config,
    @Optional()
    @Inject(IDENTITY_VERIFIER)
    private readonly verifier: IdentityVerifier | null = createIdentityVerifier(
      config,
    ),
  ) {}

  async profile(userId: string) {
    return { profile: await getProfile(this.pool, userId, this.config) };
  }

  async verification(userId: string) {
    return verifyProfile(this.pool, this.config, this.verifier, userId);
  }

  async history(userId: string, pagination: HistoryPagination) {
    return transaction(this.pool, async (client) => {
      await lockedProfile(client, userId);
      return submissionHistory(client, userId, pagination, this.config);
    });
  }

  async historyMedia(userId: string, submissionId: string, kind: MediaKind) {
    return archivedMedia(this.pool, userId, submissionId, kind, this.config);
  }

  /** Invoked by the upload guard before multipart buffering/decoding begins. */
  async assertUploadEditable(userId: string) {
    const current = await this.pool.query<Pick<ProfileRecord, "status">>(
      "SELECT status FROM kyc_profiles WHERE user_id=$1",
      [userId],
    );
    assertEditable(current.rows[0]);
  }

  async savePersonalDetails(userId: string, details: PersonalDetails) {
    return transaction(this.pool, async (client) => {
      assertEditable(await lockedProfile(client, userId));
      const encrypted = encrypt(
        Buffer.from(JSON.stringify(details)),
        this.config.mediaKey,
      ).toString("base64");
      await client.query(
        "UPDATE kyc_profiles SET personal_details=$2,status='in_progress',updated_at=now() WHERE user_id=$1",
        [userId, encrypted],
      );
      return { profile: await getProfile(client, userId, this.config) };
    });
  }

  async uploadMedia(
    userId: string,
    kind: MediaKind,
    fields: UploadFields,
    image?: UploadedImage,
  ) {
    if (!image || image.data.length === 0)
      throw new ApiError(400, "INVALID_UPLOAD", "Choose a JPEG or PNG image.");
    if (image.data.length > this.config.maxUploadBytes)
      throw new ApiError(413, "UPLOAD_TOO_LARGE", "The image is too large.");
    const validJpeg =
      image.data.length >= 3 &&
      image.data[0] === 0xff &&
      image.data[1] === 0xd8 &&
      image.data[2] === 0xff;
    const validPng =
      image.data.length >= 8 &&
      image.data
        .subarray(0, 8)
        .equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
    if (
      (!validJpeg && !validPng) ||
      !["image/jpeg", "image/png"].includes(image.mimeType)
    )
      throw new ApiError(
        400,
        "INVALID_UPLOAD",
        "Only valid JPEG and PNG images are accepted.",
      );
    let sanitized: Buffer;
    try {
      // Decode/re-encode strips EXIF/GPS and rejects corrupt or oversized images.
      sanitized = await sharp(image.data, {
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
    const documentType =
      kind === "document"
        ? documentTypeSchema.parse(fields.documentType)
        : null;
    const key = randomUUID();
    const location = join(this.config.mediaDir, key);
    await mkdir(this.config.mediaDir, { recursive: true, mode: 0o700 });
    await writeFile(location, encrypt(sanitized, this.config.mediaKey), {
      mode: 0o600,
      flag: "wx",
    });
    let oldKey: string | undefined;
    let existingCapture = false;
    try {
      const result = await transaction(this.pool, async (client) => {
        assertEditable(await lockedProfile(client, userId));
        const old = await client.query<
          Pick<MediaRecord, "storage_key" | "client_capture_id">
        >(
          "SELECT storage_key,client_capture_id FROM kyc_media WHERE user_id=$1 AND kind=$2",
          [userId, kind],
        );
        if (
          fields.captureId &&
          old.rows[0]?.client_capture_id === fields.captureId
        ) {
          existingCapture = true;
          return { profile: await getProfile(client, userId, this.config) };
        }
        oldKey = old.rows[0]?.storage_key;
        await client.query(
          "INSERT INTO kyc_media(id,user_id,kind,document_type,mime_type,size,storage_key,client_capture_id) VALUES($1,$2,$3,$4,$5,$6,$7,$8) ON CONFLICT(user_id,kind) DO UPDATE SET id=EXCLUDED.id,document_type=EXCLUDED.document_type,mime_type=EXCLUDED.mime_type,size=EXCLUDED.size,storage_key=EXCLUDED.storage_key,client_capture_id=EXCLUDED.client_capture_id,created_at=now()",
          [
            randomUUID(),
            userId,
            kind,
            documentType,
            "image/jpeg",
            sanitized.length,
            key,
            fields.captureId ?? null,
          ],
        );
        await client.query(
          "UPDATE kyc_profiles SET status='in_progress',verification=NULL,verification_attempt_id=NULL,updated_at=now() WHERE user_id=$1",
          [userId],
        );
        return { profile: await getProfile(client, userId, this.config) };
      });
      if (existingCapture) await rm(location, { force: true }).catch(() => {});
      if (oldKey)
        await removeUnreferencedMedia(this.pool, this.config, oldKey).catch(
          () => {},
        );
      return result;
    } catch (error) {
      await rm(location, { force: true });
      throw error;
    }
  }

  async readMedia(userId: string, kind: MediaKind) {
    const result = await this.pool.query<MediaRecord>(
      "SELECT * FROM kyc_media WHERE user_id=$1 AND kind=$2",
      [userId, kind],
    );
    const media = result.rows[0];
    if (!media) throw new ApiError(404, "MEDIA_NOT_FOUND", "Image not found.");
    return {
      data: decrypt(
        await readFile(join(this.config.mediaDir, media.storage_key)),
        this.config.mediaKey,
      ),
      mimeType: media.mime_type,
    };
  }

  async submit(userId: string) {
    return transaction(this.pool, async (client) => {
      const profile = await lockedProfile(client, userId);
      if (profile.status === "pending_review") {
        await ensureCurrentSubmission(client, userId);
        return { profile: await getProfile(client, userId, this.config) };
      }
      assertEditable(profile);
      if (verificationInProgress(profile, this.config))
        throw new ApiError(
          409,
          "KYC_VERIFICATION_IN_PROGRESS",
          "Wait for the identity check to finish before submitting.",
        );
      const media = await client.query(
        "SELECT kind FROM kyc_media WHERE user_id=$1",
        [userId],
      );
      if (!profile.personal_details || media.rowCount !== 2)
        throw new ApiError(
          400,
          "KYC_INCOMPLETE",
          "Complete personal details, document and selfie before submitting.",
        );
      await client.query(
        "UPDATE kyc_profiles SET status='pending_review',submitted_at=now(),required_steps='{}',rejection_reason=NULL,verification_attempt_id=NULL,updated_at=now() WHERE user_id=$1",
        [userId],
      );
      await ensureCurrentSubmission(client, userId);
      return { profile: await getProfile(client, userId, this.config) };
    });
  }

  async resubmit(userId: string) {
    let oldKeys: string[] = [];
    const result = await transaction(this.pool, async (client) => {
      const profile = await lockedProfile(client, userId);
      if (profile.status !== "rejected")
        throw new ApiError(
          409,
          "KYC_NOT_REJECTED",
          "Only a rejected profile can be reopened.",
        );
      await ensureCurrentSubmission(client, userId);
      const steps = profile.required_steps;
      const removed = await client.query<Pick<MediaRecord, "storage_key">>(
        "DELETE FROM kyc_media WHERE user_id=$1 AND kind=ANY($2::text[]) RETURNING storage_key",
        [userId, steps],
      );
      oldKeys = removed.rows.map((item) => item.storage_key);
      await client.query(
        "UPDATE kyc_profiles SET status='in_progress',personal_details=CASE WHEN $2 THEN NULL ELSE personal_details END,verification=CASE WHEN $3 THEN NULL ELSE verification END,verification_attempt_id=NULL,rejection_reason=NULL,required_steps='{}',submitted_at=NULL,current_submission_id=NULL,updated_at=now() WHERE user_id=$1",
        [
          userId,
          steps.includes("personal_details"),
          steps.includes("document") || steps.includes("selfie"),
        ],
      );
      return { profile: await getProfile(client, userId, this.config) };
    });
    await Promise.all(
      oldKeys.map((key) =>
        removeUnreferencedMedia(this.pool, this.config, key).catch(() => {}),
      ),
    );
    return result;
  }
}
