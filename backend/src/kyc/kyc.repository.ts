import { randomUUID } from "node:crypto";
import type { Pool, PoolClient } from "pg";
import { z } from "zod";
import type { Config } from "../config.js";
import { transaction } from "../database.js";
import { ApiError } from "../errors.js";
import { decrypt } from "../security.js";
import {
  requiredStepSchema,
  type MediaKind,
  type PersonalDetails,
  type RequiredStep,
} from "./kyc.schemas.js";

export type KycStatus =
  "not_started" | "in_progress" | "pending_review" | "verified" | "rejected";

export interface ProfileRecord {
  id: string;
  user_id: string;
  status: KycStatus;
  personal_details: string | null;
  rejection_reason: string | null;
  required_steps: RequiredStep[];
  submitted_at: Date | null;
  updated_at: Date;
}

export interface MediaRecord {
  id: string;
  user_id: string;
  kind: MediaKind;
  document_type: string | null;
  mime_type: string;
  size: number;
  storage_key: string;
  client_capture_id: string | null;
}

export function assertEditable(
  profile: Pick<ProfileRecord, "status"> | undefined,
) {
  if (!profile) throw new ApiError(404, "KYC_NOT_FOUND", "Profile not found.");
  if (!["not_started", "in_progress"].includes(profile.status))
    throw new ApiError(
      409,
      "KYC_LOCKED",
      "This profile cannot be edited in its current status. Rejected profiles must be reopened first.",
    );
}

export async function lockedProfile(client: PoolClient, userId: string) {
  const result = await client.query<ProfileRecord>(
    "SELECT * FROM kyc_profiles WHERE user_id=$1 FOR UPDATE",
    [userId],
  );
  const profile = result.rows[0];
  if (!profile) throw new ApiError(404, "KYC_NOT_FOUND", "Profile not found.");
  return profile;
}

const metadata = (row: MediaRecord | undefined) =>
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
  const profiles = await client.query<ProfileRecord>(
    "SELECT * FROM kyc_profiles WHERE user_id=$1",
    [userId],
  );
  const row = profiles.rows[0];
  if (!row) throw new ApiError(404, "KYC_NOT_FOUND", "Profile not found.");
  const records = await client.query<MediaRecord>(
    "SELECT * FROM kyc_media WHERE user_id=$1",
    [userId],
  );
  const document = metadata(
    records.rows.find((item) => item.kind === "document"),
  );
  const selfie = metadata(records.rows.find((item) => item.kind === "selfie"));
  const personalDetails: PersonalDetails | null = row.personal_details
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

/** Privileged CLI operation; no HTTP route exposes reviewer access. */
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
