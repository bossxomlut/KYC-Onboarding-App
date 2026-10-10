import {
  createHmac,
  randomBytes,
  createCipheriv,
  createDecipheriv,
} from "node:crypto";
import { SignJWT, jwtVerify } from "jose";
import type { Config } from "./config.js";

export const opaqueToken = () => randomBytes(32).toString("base64url");
export function tokenHash(value: string, pepper: Buffer) {
  return createHmac("sha256", pepper).update(value).digest("hex");
}
export function encrypt(bytes: Buffer, key: Buffer) {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  return Buffer.concat([
    iv,
    cipher.update(bytes),
    cipher.final(),
    cipher.getAuthTag(),
  ]);
}
export function decrypt(bytes: Buffer, key: Buffer) {
  const decipher = createDecipheriv("aes-256-gcm", key, bytes.subarray(0, 12));
  decipher.setAuthTag(bytes.subarray(-16));
  return Buffer.concat([
    decipher.update(bytes.subarray(12, -16)),
    decipher.final(),
  ]);
}
export async function accessToken(
  userId: string,
  sessionId: string,
  config: Config,
) {
  return new SignJWT({ sid: sessionId })
    .setProtectedHeader({ alg: "HS256", typ: "JWT" })
    .setSubject(userId)
    .setIssuer("kyc-onboarding-api")
    .setAudience("kyc-mobile")
    .setIssuedAt()
    .setExpirationTime("15m")
    .sign(config.jwtSecret);
}
export async function verifyAccess(token: string, config: Config) {
  const { payload } = await jwtVerify(token, config.jwtSecret, {
    issuer: "kyc-onboarding-api",
    audience: "kyc-mobile",
    algorithms: ["HS256"],
  });
  if (typeof payload.sub !== "string" || typeof payload.sid !== "string")
    throw new Error("Invalid claims");
  return { userId: payload.sub, sessionId: payload.sid };
}
