import { randomUUID } from "node:crypto";
import { readFile, rm } from "node:fs/promises";
import { join } from "node:path";
import type { Pool, PoolClient } from "pg";
import type { UserRole } from "../auth/roles.js";
import type { Config } from "../config.js";
import { ApiError } from "../errors.js";
import { decrypt } from "../security.js";
import type { MediaKind, PersonalDetails } from "./kyc.schemas.js";
import type { HistoryPagination } from "./kyc-history.schemas.js";

interface SubmissionRecord {
  id: string;
  user_id: string;
  profile_id: string;
  version: number;
  personal_details: string | null;
  status: "pending_review" | "verified" | "rejected";
  rejection_reason: string | null;
  required_steps: string[];
  submitted_at: Date | null;
  updated_at: Date;
  review_decision: "verified" | "rejected" | null;
  review_reason: string | null;
  review_required_steps: string[];
  reviewed_at: Date | null;
  reviewed_by: string | null;
  reviewer_email: string | null;
  reviewer_role: UserRole | null;
}

interface ArchivedMedia {
  submission_id: string;
  kind: MediaKind;
  media_id: string;
  document_type: string | null;
  mime_type: string;
  size: number;
  storage_key: string;
  client_capture_id: string | null;
}

/** Caller owns the profile row lock. Copy encrypted values and immutable file
 * references before a review or resubmission can change the live profile. */
export async function ensureCurrentSubmission(
  client: PoolClient,
  userId: string,
) {
  const existing = await client.query<{ id: string }>(
    "SELECT s.id FROM kyc_submissions s JOIN kyc_profiles p ON p.current_submission_id=s.id AND s.user_id=p.user_id WHERE p.user_id=$1 AND s.status=p.status AND s.submitted_at IS NOT DISTINCT FROM p.submitted_at",
    [userId],
  );
  if (existing.rows[0]) return existing.rows[0].id;
  const id = randomUUID();
  const inserted = await client.query(
    "INSERT INTO kyc_submissions(id,user_id,profile_id,version,personal_details,status,rejection_reason,required_steps,submitted_at,updated_at,review_decision,review_reason,review_required_steps,reviewed_at,reviewed_by) SELECT $2,p.user_id,p.id,COALESCE((SELECT max(version) FROM kyc_submissions WHERE user_id=$1),0)+1,p.personal_details,p.status,p.rejection_reason,p.required_steps,p.submitted_at,p.updated_at,CASE WHEN a.decision=p.status THEN a.decision END,CASE WHEN a.decision=p.status THEN COALESCE(a.reason,CASE WHEN p.status='rejected' THEN p.rejection_reason END) END,CASE WHEN a.decision=p.status THEN a.required_steps ELSE '{}'::text[] END,CASE WHEN a.decision=p.status THEN a.created_at END,CASE WHEN a.decision=p.status THEN a.reviewed_by END FROM kyc_profiles p LEFT JOIN LATERAL (SELECT * FROM kyc_reviews r WHERE r.user_id=p.user_id AND (p.submitted_at IS NULL OR r.created_at>=p.submitted_at) ORDER BY r.created_at DESC,r.id DESC LIMIT 1) a ON p.status IN ('verified','rejected') WHERE p.user_id=$1 AND p.status IN ('pending_review','verified','rejected') RETURNING id",
    [userId, id],
  );
  if (inserted.rowCount !== 1)
    throw new ApiError(
      409,
      "KYC_NOT_SUBMITTED",
      "This profile has not been submitted.",
    );
  await client.query(
    "INSERT INTO kyc_submission_media(submission_id,kind,media_id,document_type,mime_type,size,storage_key,client_capture_id) SELECT $2,kind,id,document_type,mime_type,size,storage_key,client_capture_id FROM kyc_media WHERE user_id=$1",
    [userId, id],
  );
  await client.query(
    "UPDATE kyc_profiles SET current_submission_id=$2 WHERE user_id=$1",
    [userId, id],
  );
  return id;
}

export async function recordSubmissionReview(
  client: PoolClient,
  submissionId: string,
  actor: { id: string; email_normalized: string; role: UserRole },
  decision: "verified" | "rejected",
  reason: string | null,
  requiredSteps: string[],
) {
  const result = await client.query(
    "UPDATE kyc_submissions SET status=$2,rejection_reason=$3,required_steps=$4,updated_at=now(),review_decision=$2,review_reason=$3,review_required_steps=$4,reviewed_at=now(),reviewed_by=$5,reviewer_email=$6,reviewer_role=$7 WHERE id=$1 AND status='pending_review' AND review_decision IS NULL",
    [
      submissionId,
      decision,
      reason,
      requiredSteps,
      actor.id,
      actor.email_normalized,
      actor.role,
    ],
  );
  if (result.rowCount !== 1)
    throw new ApiError(
      409,
      "KYC_REVIEW_NOT_PENDING",
      "Only pending submissions can be reviewed.",
    );
}

const metadata = (row: ArchivedMedia | undefined) =>
  row
    ? {
        id: row.media_id,
        mimeType: row.mime_type,
        size: row.size,
        ...(row.client_capture_id ? { captureId: row.client_capture_id } : {}),
        ...(row.kind === "document" ? { documentType: row.document_type } : {}),
      }
    : null;

export async function submissionHistory(
  client: Pool | PoolClient,
  userId: string,
  pagination: HistoryPagination,
  config: Config,
) {
  const rows = await client.query<SubmissionRecord>(
    "SELECT * FROM kyc_submissions WHERE user_id=$1 ORDER BY version DESC LIMIT $2 OFFSET $3",
    [userId, pagination.limit, pagination.offset],
  );
  const media = rows.rows.length
    ? await client.query<ArchivedMedia>(
        "SELECT * FROM kyc_submission_media WHERE submission_id=ANY($1::uuid[])",
        [rows.rows.map((row) => row.id)],
      )
    : { rows: [] as ArchivedMedia[] };
  const count = await client.query<{ total: string }>(
    "SELECT count(*) AS total FROM kyc_submissions WHERE user_id=$1",
    [userId],
  );
  return {
    submissions: rows.rows.map((row) => {
      const photos = media.rows.filter(
        (photo) => photo.submission_id === row.id,
      );
      const personalDetails: PersonalDetails | null = row.personal_details
        ? JSON.parse(
            decrypt(
              Buffer.from(row.personal_details, "base64"),
              config.mediaKey,
            ).toString("utf8"),
          )
        : null;
      return {
        id: row.id,
        version: row.version,
        profile: {
          id: row.profile_id,
          status: row.status,
          nextStep: "result",
          personalDetails,
          document: metadata(photos.find((photo) => photo.kind === "document")),
          selfie: metadata(photos.find((photo) => photo.kind === "selfie")),
          rejectionReason: row.rejection_reason,
          requiredSteps: row.required_steps,
          submittedAt: row.submitted_at?.toISOString() ?? null,
          updatedAt: row.updated_at.toISOString(),
        },
        review:
          row.review_decision && row.reviewed_at
            ? {
                decision: row.review_decision,
                reason: row.review_reason,
                requiredSteps: row.review_required_steps,
                reviewedAt: row.reviewed_at.toISOString(),
                reviewer: row.reviewed_by
                  ? {
                      id: row.reviewed_by,
                      email: row.reviewer_email,
                      role: row.reviewer_role,
                    }
                  : null,
              }
            : null,
      };
    }),
    total: Number(count.rows[0]!.total),
  };
}

export async function archivedMedia(
  client: Pool | PoolClient,
  userId: string,
  submissionId: string,
  kind: MediaKind,
  config: Config,
) {
  const rows = await client.query<ArchivedMedia>(
    "SELECT m.* FROM kyc_submission_media m JOIN kyc_submissions s ON s.id=m.submission_id WHERE s.user_id=$1 AND s.id=$2 AND m.kind=$3",
    [userId, submissionId, kind],
  );
  const media = rows.rows[0];
  if (!media) throw new ApiError(404, "MEDIA_NOT_FOUND", "Image not found.");
  return {
    data: decrypt(
      await readFile(join(config.mediaDir, media.storage_key)),
      config.mediaKey,
    ),
    mimeType: media.mime_type,
  };
}

/** A file can be shared by live and archived versions without copying bytes. */
export async function removeUnreferencedMedia(
  pool: Pool,
  config: Config,
  key: string,
) {
  const references = await pool.query(
    "SELECT 1 FROM kyc_media WHERE storage_key=$1 UNION ALL SELECT 1 FROM kyc_submission_media WHERE storage_key=$1 LIMIT 1",
    [key],
  );
  if (references.rowCount === 0)
    await rm(join(config.mediaDir, key), { force: true });
}
