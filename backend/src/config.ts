import "dotenv/config";
import { resolve } from "node:path";
import { z } from "zod";

export interface Config {
  nodeEnv: string;
  host: string;
  port: number;
  databaseUrl: string;
  jwtSecret: Buffer;
  tokenPepper: Buffer;
  mediaKey: Buffer;
  mediaDir: string;
  smtpHost: string;
  smtpPort: number;
  smtpSecure: boolean;
  smtpUser?: string;
  smtpPassword?: string;
  mailFrom: string;
  resetLink: string;
  rateLimitMax: number;
  maxUploadBytes: number;
}

function key(name: string): Buffer {
  const value = process.env[name];
  if (!value || value.startsWith("replace-"))
    throw new Error(
      `${name} must be a random 32-byte base64 value. See .env.example.`,
    );
  const bytes = Buffer.from(value, "base64");
  if (bytes.length !== 32)
    throw new Error(`${name} must contain exactly 32 bytes.`);
  return bytes;
}
export function loadConfig(): Config {
  const env = z
    .object({
      NODE_ENV: z
        .enum(["development", "test", "production"])
        .default("development"),
      HOST: z.string().default("0.0.0.0"),
      PORT: z.coerce.number().int().min(1).max(65535).default(3000),
      DATABASE_URL: z.string().min(1),
      SMTP_HOST: z.string().default("localhost"),
      SMTP_PORT: z.coerce.number().int().default(1025),
      SMTP_SECURE: z.enum(["true", "false"]).default("false"),
      RATE_LIMIT_MAX: z.coerce.number().int().min(1).default(12),
      MAX_UPLOAD_BYTES: z.coerce
        .number()
        .int()
        .min(1024)
        .max(10 * 1024 * 1024)
        .default(10 * 1024 * 1024),
    })
    .parse(process.env);
  if (env.NODE_ENV === "production" && env.SMTP_SECURE !== "true")
    throw new Error("Production requires TLS SMTP.");
  return {
    nodeEnv: env.NODE_ENV,
    host: env.HOST,
    port: env.PORT,
    databaseUrl: env.DATABASE_URL,
    jwtSecret: key("JWT_SECRET"),
    tokenPepper: key("TOKEN_PEPPER"),
    mediaKey: key("MEDIA_ENCRYPTION_KEY"),
    mediaDir: resolve(process.env.MEDIA_DIR ?? "media"),
    smtpHost: env.SMTP_HOST,
    smtpPort: env.SMTP_PORT,
    smtpSecure: env.SMTP_SECURE === "true",
    smtpUser: process.env.SMTP_USER,
    smtpPassword: process.env.SMTP_PASSWORD,
    mailFrom: process.env.MAIL_FROM ?? "KYC Demo <no-reply@kyc.example>",
    resetLink: process.env.RESET_LINK ?? "kycapp://app/reset-password",
    rateLimitMax: env.RATE_LIMIT_MAX,
    maxUploadBytes: env.MAX_UPLOAD_BYTES,
  };
}
