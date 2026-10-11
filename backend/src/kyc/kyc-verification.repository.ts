import type { Config, LocalOcrLanguages } from "../config.js";
import { decrypt } from "../security.js";
import type { IdentityCheckResult } from "../verification/identity-verifier.js";

export interface KycVerification {
  provider: "aws" | "local" | "none";
  ocrLanguages?: LocalOcrLanguages;
  status: "disabled" | "not_started" | "completed" | "failed";
  documentId: string | null;
  selfieId: string | null;
  checkedAt: string | null;
  ocr: IdentityCheckResult["ocr"] | null;
  selfieFace: IdentityCheckResult["selfieFace"] | null;
  faceMatch: IdentityCheckResult["faceMatch"] | null;
}

export function verificationMatchesConfig(
  verification: KycVerification,
  config: Config,
): boolean {
  const active = config.verification;
  return (
    !active ||
    (verification.provider === active.provider &&
      verification.selfieFace != null &&
      verification.faceMatch?.threshold === active.faceMatchThreshold &&
      (active.provider !== "local" ||
        verification.ocrLanguages === active.ocrLanguages))
  );
}

export function verificationView(
  encrypted: string | null | undefined,
  config: Config,
): KycVerification {
  if (encrypted) {
    const stored = JSON.parse(
      decrypt(Buffer.from(encrypted, "base64"), config.mediaKey).toString(
        "utf8",
      ),
    ) as KycVerification;
    // Historical evidence predates the separate selfie check. Never infer it
    // from a combined faceMatch status, which may describe the document.
    return { ...stored, selfieFace: stored.selfieFace ?? null };
  }
  return {
    provider: config.verification?.provider ?? "none",
    status: config.verification ? "not_started" : "disabled",
    documentId: null,
    selfieId: null,
    checkedAt: null,
    ocr: null,
    selfieFace: null,
    faceMatch: null,
  };
}

export function verificationInProgress(
  profile: {
    verification_attempt_id?: string | null;
    verification_started_at?: Date | null;
  },
  config: Config,
) {
  return Boolean(
    profile.verification_attempt_id &&
    profile.verification_started_at &&
    Date.now() - profile.verification_started_at.getTime() <
      (config.verification?.timeoutMs ?? 7000) + 1000,
  );
}
