import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import type { Pool } from "pg";
import type { Config } from "../config.js";
import { transaction } from "../database.js";
import { ApiError } from "../errors.js";
import { decrypt, encrypt } from "../security.js";
import type {
  IdentityCheckResult,
  IdentityVerifier,
} from "../verification/identity-verifier.js";
import {
  assertEditable,
  getProfile,
  lockedProfile,
  type MediaRecord,
} from "./kyc.repository.js";
import {
  verificationInProgress,
  verificationMatchesConfig,
  verificationView,
  type KycVerification,
} from "./kyc-verification.repository.js";

const cooldownMs = 30_000;

/** Claim an attempt under the profile lock, call the provider without a database
 * transaction, then commit only against the same editable media version. */
export async function verifyProfile(
  pool: Pool,
  config: Config,
  verifier: IdentityVerifier | null,
  userId: string,
) {
  const attemptId = randomUUID();
  const input = await transaction(pool, async (client) => {
    const profile = await lockedProfile(client, userId);
    assertEditable(profile);
    if (!verifier || !config.verification)
      throw new ApiError(
        503,
        "VERIFICATION_NOT_CONFIGURED",
        "Identity checks are not configured. You can continue with manual review.",
      );
    const media = await client.query<MediaRecord>(
      "SELECT * FROM kyc_media WHERE user_id=$1",
      [userId],
    );
    const document = media.rows.find((row) => row.kind === "document");
    const selfie = media.rows.find((row) => row.kind === "selfie");
    if (!document || !selfie)
      throw new ApiError(
        400,
        "KYC_VERIFICATION_INCOMPLETE",
        "Upload a document and selfie before checking identity.",
      );
    const previous = verificationView(profile.verification, config);
    if (
      previous.status === "completed" &&
      verificationMatchesConfig(previous, config) &&
      previous.documentId === document.id &&
      previous.selfieId === selfie.id
    ) {
      return { cached: { profile: await getProfile(client, userId, config) } };
    }
    if (verificationInProgress(profile, config))
      throw new ApiError(
        409,
        "KYC_VERIFICATION_IN_PROGRESS",
        "An identity check is already in progress. Try again shortly.",
      );
    if (
      profile.verification_started_at &&
      Date.now() - profile.verification_started_at.getTime() < cooldownMs
    )
      throw new ApiError(
        429,
        "KYC_VERIFICATION_RATE_LIMITED",
        "Wait 30 seconds between identity checks.",
      );
    // Read while owning the lock: replacement cleanup cannot remove these files.
    const [documentBytes, selfieBytes] = await Promise.all([
      readFile(join(config.mediaDir, document.storage_key)),
      readFile(join(config.mediaDir, selfie.storage_key)),
    ]);
    const bytes = {
      document: decrypt(documentBytes, config.mediaKey),
      selfie: decrypt(selfieBytes, config.mediaKey),
    };
    await client.query(
      "UPDATE kyc_profiles SET verification_attempt_id=$2,verification_started_at=now() WHERE user_id=$1",
      [userId, attemptId],
    );
    return { documentId: document.id, selfieId: selfie.id, bytes };
  });
  if (input.cached) return input.cached;

  let result: IdentityCheckResult;
  try {
    result = await verifier!.verify(input.bytes!.document, input.bytes!.selfie);
  } catch {
    // Never expose cloud exception messages, document bytes or credentials.
    result = {
      ocr: {
        status: "failed",
        text: "",
        fields: { fullName: null, dateOfBirth: null, documentNumber: null },
        confidence: null,
      },
      faceMatch: {
        status: "failed",
        similarity: null,
        threshold: config.verification!.faceMatchThreshold,
      },
    };
  }
  const verification: KycVerification = {
    provider: config.verification!.provider,
    ...(config.verification!.provider === "local"
      ? { ocrLanguages: config.verification!.ocrLanguages }
      : {}),
    status:
      result.ocr.status === "failed" || result.faceMatch.status === "failed"
        ? "failed"
        : "completed",
    documentId: input.documentId!,
    selfieId: input.selfieId!,
    checkedAt: new Date().toISOString(),
    ocr: result.ocr,
    faceMatch: result.faceMatch,
  };
  return transaction(pool, async (client) => {
    const profile = await lockedProfile(client, userId);
    const media = await client.query<Pick<MediaRecord, "id" | "kind">>(
      "SELECT id,kind FROM kyc_media WHERE user_id=$1",
      [userId],
    );
    if (
      profile.verification_attempt_id !== attemptId ||
      !["not_started", "in_progress"].includes(profile.status) ||
      media.rows.find((row) => row.kind === "document")?.id !==
        input.documentId ||
      media.rows.find((row) => row.kind === "selfie")?.id !== input.selfieId
    ) {
      throw new ApiError(
        409,
        "KYC_VERIFICATION_CHANGED",
        "The photos or profile changed during the identity check. Check the current photos again.",
      );
    }
    const encrypted = encrypt(
      Buffer.from(JSON.stringify(verification)),
      config.mediaKey,
    ).toString("base64");
    await client.query(
      "UPDATE kyc_profiles SET verification=$2,verification_attempt_id=NULL,updated_at=now() WHERE user_id=$1",
      [userId, encrypted],
    );
    return { profile: await getProfile(client, userId, config) };
  });
}
