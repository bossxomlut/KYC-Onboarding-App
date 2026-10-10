import { randomInt, randomUUID, timingSafeEqual } from "node:crypto";
import argon2 from "argon2";
import type { Pool, PoolClient } from "pg";
import type { FastifyInstance, FastifyRequest } from "fastify";
import { z } from "zod";
import type { Config } from "./config.js";
import type { Mailer, Mail } from "./mail.js";
import { queueMail, deliverQueued } from "./mail.js";
import { ApiError } from "./errors.js";
import { transaction } from "./database.js";
import {
  accessToken,
  opaqueToken,
  tokenHash,
  verifyAccess,
} from "./security.js";

declare module "fastify" {
  interface FastifyRequest {
    userId: string;
  }
}
const emailSchema = z.string().trim().toLowerCase().max(254).email();
const passwordSchema = z
  .string()
  .min(12)
  .max(128)
  .refine(
    (value) => /[a-z]/.test(value) && /[A-Z]/.test(value) && /\d/.test(value),
    {
      message:
        "Use at least 12 characters with upper-case, lower-case and a number.",
    },
  );
const credentials = z.strictObject({
  email: emailSchema,
  password: passwordSchema,
});
const loginBody = z.strictObject({
  email: emailSchema,
  password: z.string().min(1).max(128),
});
const emailBody = z.strictObject({ email: emailSchema });
const refreshBody = z.strictObject({
  refreshToken: z.string().min(1).max(256),
});
const genericMessage = {
  message:
    "If this email is registered, instructions will arrive shortly. Check your inbox and retry later if no email arrives.",
};
const publicUser = (row: any) => ({
  id: row.id,
  email: row.email_normalized,
  emailVerified: row.email_verified_at !== null,
});
export const passwordHash = (password: string) =>
  argon2.hash(password, {
    type: argon2.argon2id,
    memoryCost: 19456,
    timeCost: 2,
    parallelism: 1,
  });

async function issueSession(
  client: PoolClient,
  user: any,
  config: Config,
  familyId = randomUUID(),
) {
  const id = randomUUID();
  const refreshToken = opaqueToken();
  await client.query(
    "INSERT INTO auth_sessions(id,user_id,family_id,refresh_token_hash,expires_at) VALUES($1,$2,$3,$4,now()+interval '30 days')",
    [id, user.id, familyId, tokenHash(refreshToken, config.tokenPepper)],
  );
  return {
    sessionId: id,
    user: publicUser(user),
    accessToken: await accessToken(user.id, id, config),
    refreshToken,
    expiresIn: 900,
  };
}
function sessionResponse(session: Awaited<ReturnType<typeof issueSession>>) {
  const { sessionId, ...response } = session;
  return response;
}
async function createOtp(client: PoolClient, user: any, config: Config) {
  const code = String(randomInt(100000, 1000000));
  await client.query(
    "UPDATE email_verification_tokens SET consumed_at=now() WHERE user_id=$1 AND consumed_at IS NULL",
    [user.id],
  );
  await client.query(
    "INSERT INTO email_verification_tokens(id,user_id,code_hash,expires_at) VALUES($1,$2,$3,now()+interval '10 minutes')",
    [
      randomUUID(),
      user.id,
      tokenHash(`${user.id}:${code}`, config.tokenPepper),
    ],
  );
  return queueMail(client, config, user.id, "verification", {
    to: user.email_normalized,
    subject: "Verify your KYC email",
    text: `Your verification code is ${code}. It expires in 10 minutes. If you did not request this, ignore this email.`,
  });
}
export function authentication(pool: Pool, config: Config) {
  return async (request: FastifyRequest) => {
    const header = request.headers.authorization;
    if (!header?.startsWith("Bearer "))
      throw new ApiError(401, "SESSION_EXPIRED", "Please sign in to continue.");
    let claims: { userId: string; sessionId: string };
    try {
      claims = await verifyAccess(header.substring(7), config);
    } catch {
      throw new ApiError(
        401,
        "SESSION_EXPIRED",
        "Your session has expired. Please sign in again.",
      );
    }
    const active = await pool.query(
      "SELECT 1 FROM auth_sessions s JOIN users u ON u.id=s.user_id WHERE s.id=$1 AND s.user_id=$2 AND s.revoked_at IS NULL AND s.expires_at>now() AND u.status='active'",
      [claims.sessionId, claims.userId],
    );
    if (!active.rowCount)
      throw new ApiError(
        401,
        "SESSION_EXPIRED",
        "Your session has expired. Please sign in again.",
      );
    request.userId = claims.userId;
  };
}

export async function registerAuth(
  app: FastifyInstance,
  pool: Pool,
  config: Config,
  mailer: Mailer,
) {
  const dummyPasswordHash = await passwordHash(opaqueToken());
  const rate = {
    config: { rateLimit: { max: config.rateLimitMax, timeWindow: "1 minute" } },
  };
  app.post("/api/v1/auth/register", rate, async (request, reply) => {
    const { email, password } = credentials.parse(request.body);
    const hash = await passwordHash(password);
    let result: { user: any; mail: Mail };
    try {
      result = await transaction(pool, async (client) => {
        const insert = await client.query(
          "INSERT INTO users(id,email_normalized,password_hash) VALUES($1,$2,$3) ON CONFLICT(email_normalized) DO NOTHING RETURNING *",
          [randomUUID(), email, hash],
        );
        const user = insert.rows[0];
        if (!user)
          throw new ApiError(
            409,
            "ACCOUNT_EXISTS",
            "An account already exists. Sign in or resend verification.",
          );
        await client.query(
          "INSERT INTO kyc_profiles(id,user_id) VALUES($1,$2)",
          [randomUUID(), user.id],
        );
        return { user, mail: await createOtp(client, user, config) };
      });
    } catch (error) {
      if ((error as { code?: string }).code === "23505")
        throw new ApiError(
          409,
          "ACCOUNT_EXISTS",
          "An account already exists. Sign in or resend verification.",
        );
      throw error;
    }
    if (!(await deliverQueued(pool, config, mailer, result.mail.id)))
      throw new ApiError(
        503,
        "EMAIL_DELIVERY_FAILED",
        "Email delivery is temporarily unavailable. Your account was saved and the email is queued. Retry verification shortly.",
      );
    return reply
      .code(201)
      .send({ user: publicUser(result.user), nextStep: "VERIFY_EMAIL" });
  });
  app.post("/api/v1/auth/email/resend", rate, async (request) => {
    const { email } = emailBody.parse(request.body);
    await transaction(pool, async (client) => {
      const result = await client.query(
        "SELECT * FROM users WHERE email_normalized=$1 FOR UPDATE",
        [email],
      );
      const user = result.rows[0];
      if (!user || user.email_verified_at || user.status === "disabled")
        return null;
      const recent = await client.query(
        "SELECT 1 FROM email_verification_tokens WHERE user_id=$1 AND created_at>now()-interval '30 seconds'",
        [user.id],
      );
      if (recent.rowCount) return null;
      return createOtp(client, user, config);
    });
    // Deliver through the worker so SMTP latency cannot distinguish account existence.
    return genericMessage;
  });
  app.post("/api/v1/auth/email/verify", rate, async (request) => {
    const { email, code } = z
      .strictObject({ email: emailSchema, code: z.string().regex(/^\d{6}$/) })
      .parse(request.body);
    const result = await transaction(pool, async (client) => {
      const users = await client.query(
        "SELECT * FROM users WHERE email_normalized=$1 FOR UPDATE",
        [email],
      );
      const user = users.rows[0];
      if (!user || user.email_verified_at || user.status === "disabled")
        return { error: "OTP_INVALID" } as const;
      const tokens = await client.query(
        "SELECT * FROM email_verification_tokens WHERE user_id=$1 AND consumed_at IS NULL ORDER BY created_at DESC LIMIT 1 FOR UPDATE",
        [user.id],
      );
      const token = tokens.rows[0];
      if (!token || token.attempt_count >= 5)
        return { error: "OTP_INVALID" } as const;
      if (new Date(token.expires_at).getTime() <= Date.now())
        return { error: "OTP_EXPIRED" } as const;
      const hash = tokenHash(`${user.id}:${code}`, config.tokenPepper);
      if (!timingSafeEqual(Buffer.from(hash), Buffer.from(token.code_hash))) {
        await client.query(
          "UPDATE email_verification_tokens SET attempt_count=attempt_count+1 WHERE id=$1",
          [token.id],
        );
        return { error: "OTP_INVALID" } as const;
      }
      await client.query(
        "UPDATE email_verification_tokens SET consumed_at=now() WHERE id=$1",
        [token.id],
      );
      const verified = await client.query(
        "UPDATE users SET email_verified_at=now(),status='active',updated_at=now() WHERE id=$1 RETURNING *",
        [user.id],
      );
      return { session: await issueSession(client, verified.rows[0], config) };
    });
    if ("error" in result)
      throw new ApiError(
        400,
        result.error!,
        result.error === "OTP_EXPIRED"
          ? "Verification code expired. Please request a new code."
          : "Invalid verification code. Check the code or request a new one.",
      );
    return sessionResponse(result.session);
  });
  app.post("/api/v1/auth/login", rate, async (request) => {
    const { email, password } = loginBody.parse(request.body);
    return transaction(pool, async (client) => {
      const users = await client.query(
        "SELECT * FROM users WHERE email_normalized=$1 FOR UPDATE",
        [email],
      );
      const user = users.rows[0];
      const passwordMatches = await argon2.verify(
        user?.password_hash ?? dummyPasswordHash,
        password,
      );
      if (!user || user.status === "disabled" || !passwordMatches)
        throw new ApiError(
          401,
          "INVALID_CREDENTIALS",
          "Unable to sign in with the provided credentials.",
        );
      if (!user.email_verified_at)
        throw new ApiError(
          403,
          "EMAIL_NOT_VERIFIED",
          "Please verify your email before signing in.",
        );
      return sessionResponse(await issueSession(client, user, config));
    });
  });
  app.post("/api/v1/auth/refresh", rate, async (request) => {
    const { refreshToken } = refreshBody.parse(request.body);
    const result = await transaction(pool, async (client) => {
      const ownership = await client.query(
        "SELECT user_id,family_id FROM auth_sessions WHERE refresh_token_hash=$1",
        [tokenHash(refreshToken, config.tokenPepper)],
      );
      const owner = ownership.rows[0];
      if (!owner) return null;
      // Lock the user before sessions so reset/login/refresh share a consistent ordering.
      await client.query("SELECT id FROM users WHERE id=$1 FOR UPDATE", [
        owner.user_id,
      ]);
      await client.query(
        "SELECT pg_advisory_xact_lock(hashtextextended($1,0))",
        [owner.family_id],
      );
      const records = await client.query(
        "SELECT s.*,u.email_normalized,u.email_verified_at,u.status AS user_status FROM auth_sessions s JOIN users u ON u.id=s.user_id WHERE s.refresh_token_hash=$1 FOR UPDATE OF s",
        [tokenHash(refreshToken, config.tokenPepper)],
      );
      const old = records.rows[0];
      if (!old) return null;
      if (old.revoked_at || old.replaced_by_session_id) {
        await client.query(
          "UPDATE auth_sessions SET revoked_at=COALESCE(revoked_at,now()) WHERE family_id=$1",
          [old.family_id],
        );
        return null;
      }
      if (
        new Date(old.expires_at).getTime() <= Date.now() ||
        old.user_status !== "active"
      )
        return null;
      const next = await issueSession(
        client,
        { ...old, id: old.user_id },
        config,
        old.family_id,
      );
      await client.query(
        "UPDATE auth_sessions SET revoked_at=now(),replaced_by_session_id=$2,last_used_at=now() WHERE id=$1",
        [old.id, next.sessionId],
      );
      return sessionResponse(next);
    });
    if (!result)
      throw new ApiError(
        401,
        "SESSION_EXPIRED",
        "Your session has expired. Please sign in again.",
      );
    return result;
  });
  app.post("/api/v1/auth/logout", async (request) => {
    const { refreshToken } = refreshBody.parse(request.body);
    await transaction(pool, async (client) => {
      const records = await client.query(
        "SELECT family_id FROM auth_sessions WHERE refresh_token_hash=$1",
        [tokenHash(refreshToken, config.tokenPepper)],
      );
      const family = records.rows[0]?.family_id;
      if (!family) return;
      await client.query(
        "SELECT pg_advisory_xact_lock(hashtextextended($1,0))",
        [family],
      );
      await client.query(
        "UPDATE auth_sessions SET revoked_at=COALESCE(revoked_at,now()) WHERE family_id=$1",
        [family],
      );
    });
    return { success: true };
  });
  app.get(
    "/api/v1/auth/me",
    { preHandler: authentication(pool, config) },
    async (request) => {
      const user = await pool.query("SELECT * FROM users WHERE id=$1", [
        request.userId,
      ]);
      return { user: publicUser(user.rows[0]) };
    },
  );
  app.post("/api/v1/auth/password/forgot", rate, async (request) => {
    const { email } = emailBody.parse(request.body);
    await transaction(pool, async (client) => {
      const users = await client.query(
        "SELECT * FROM users WHERE email_normalized=$1 AND status<>'disabled' FOR UPDATE",
        [email],
      );
      const user = users.rows[0];
      if (!user) return null;
      const token = opaqueToken();
      await client.query(
        "UPDATE password_reset_tokens SET consumed_at=now() WHERE user_id=$1 AND consumed_at IS NULL",
        [user.id],
      );
      await client.query(
        "INSERT INTO password_reset_tokens(id,user_id,token_hash,expires_at) VALUES($1,$2,$3,now()+interval '30 minutes')",
        [randomUUID(), user.id, tokenHash(token, config.tokenPepper)],
      );
      const separator = config.resetLink.includes("?") ? "&" : "?";
      return queueMail(client, config, user.id, "reset", {
        to: email,
        subject: "Reset your KYC password",
        text: `Reset your password: ${config.resetLink}${separator}token=${token}\nThis link expires in 30 minutes and can be used once. If you did not request this, ignore this email.`,
      });
    });
    // Keep the response generic and independent of SMTP availability/latency.
    return genericMessage;
  });
  app.post("/api/v1/auth/password/reset", rate, async (request) => {
    const { token, newPassword } = z
      .strictObject({
        token: z.string().min(1).max(256),
        newPassword: passwordSchema,
      })
      .parse(request.body);
    const hash = await passwordHash(newPassword);
    const success = await transaction(pool, async (client) => {
      const ownership = await client.query(
        "SELECT user_id FROM password_reset_tokens WHERE token_hash=$1",
        [tokenHash(token, config.tokenPepper)],
      );
      const owner = ownership.rows[0];
      if (!owner) return false;
      const user = await client.query(
        "SELECT * FROM users WHERE id=$1 FOR UPDATE",
        [owner.user_id],
      );
      const tokens = await client.query(
        "SELECT * FROM password_reset_tokens WHERE token_hash=$1 FOR UPDATE",
        [tokenHash(token, config.tokenPepper)],
      );
      const reset = tokens.rows[0];
      if (
        !reset ||
        reset.consumed_at ||
        new Date(reset.expires_at).getTime() <= Date.now()
      )
        return false;
      if (user.rows[0].status === "disabled") return false;
      await client.query(
        "UPDATE users SET password_hash=$2,updated_at=now() WHERE id=$1",
        [reset.user_id, hash],
      );
      await client.query(
        "UPDATE password_reset_tokens SET consumed_at=now() WHERE user_id=$1 AND consumed_at IS NULL",
        [reset.user_id],
      );
      await client.query(
        "UPDATE auth_sessions SET revoked_at=COALESCE(revoked_at,now()) WHERE user_id=$1",
        [reset.user_id],
      );
      return true;
    });
    if (!success)
      throw new ApiError(
        400,
        "RESET_TOKEN_INVALID",
        "The reset link is invalid or expired. Please request a new link.",
      );
    return { success: true };
  });
}
