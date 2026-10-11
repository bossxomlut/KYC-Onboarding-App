import type { Config } from "../config.js";
import { decrypt } from "../security.js";
import type { IdentityCheckResult } from "../verification/identity-verifier.js";

export interface KycVerification {
  provider: "aws" | "none";
  status: "disabled" | "not_started" | "completed" | "failed";
  documentId: string | null;
  selfieId: string | null;
  checkedAt: string | null;
  ocr: IdentityCheckResult["ocr"] | null;
  faceMatch: IdentityCheckResult["faceMatch"] | null;
}

export function verificationView(
  encrypted: string | null | undefined,
  config: Config,
): KycVerification {
  if (encrypted) {
    return JSON.parse(
      decrypt(Buffer.from(encrypted, "base64"), config.mediaKey).toString(
        "utf8",
      ),
    ) as KycVerification;
  }
  return {
    provider: config.verification?.provider ?? "none",
    status: config.verification ? "not_started" : "disabled",
    documentId: null,
    selfieId: null,
    checkedAt: null,
    ocr: null,
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
