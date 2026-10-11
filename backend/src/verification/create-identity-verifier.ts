import type { Config } from "../config.js";
import { createIdentityVerifier as createAwsIdentityVerifier } from "./aws-identity-verifier.js";
import type { IdentityVerifier } from "./identity-verifier.js";
import { LocalIdentityVerifier } from "./local-identity-verifier.js";

export function createIdentityVerifier(
  config: Config,
): IdentityVerifier | null {
  if (!config.verification) return null;
  if (config.verification.provider === "aws")
    return createAwsIdentityVerifier(config);
  const { pythonPath, modelsDir, faceMatchThreshold, timeoutMs, ocrLanguages } =
    config.verification;
  return new LocalIdentityVerifier(
    pythonPath,
    modelsDir,
    faceMatchThreshold,
    timeoutMs,
    undefined,
    ocrLanguages,
  );
}
