import { randomInt, randomUUID, timingSafeEqual } from "node:crypto";
import argon2 from "argon2";
import { Inject, Injectable, type OnModuleInit } from "@nestjs/common";
import type { Pool, PoolClient } from "pg";
import type { Config } from "../config.js";
import type { Mailer, Mail } from "../mail.js";
import { queueMail, deliverQueued } from "../mail.js";
import { ApiError } from "../errors.js";
import { transaction } from "../database.js";
import { accessToken, opaqueToken, tokenHash } from "../security.js";
import { APP_CONFIG, DATABASE_POOL, MAILER } from "../infrastructure/tokens.js";
import type {
  RegisterDto,
  LoginDto,
  EmailDto,
  VerifyEmailDto,
  RefreshDto,
  ResetPasswordDto,
} from "./auth.dto.js";
import { passwordHash } from "./password.js";

const genericMessage = {
  message:
    "If this email is registered, a code will arrive shortly. Check your inbox and retry later if no email arrives.",
};
const publicUser = (row: any) => ({
  id: row.id,
  email: row.email_normalized,
  emailVerified: row.email_verified_at !== null,
  role: row.role,
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
export async function createOtp(client: PoolClient, user: any, config: Config) {
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

async function createResetOtp(client: PoolClient, user: any, config: Config) {
  await client.query(
    "UPDATE password_reset_tokens SET consumed_at=now() WHERE user_id=$1 AND consumed_at IS NULL",
    [user.id],
  );
  // Retain hash uniqueness so a resend cannot accidentally reissue an old code.
  for (let attempt = 0; attempt < 5; attempt++) {
    const code = String(randomInt(100000, 1000000));
    const inserted = await client.query(
      "INSERT INTO password_reset_tokens(id,user_id,token_hash,expires_at) VALUES($1,$2,$3,now()+interval '10 minutes') ON CONFLICT(token_hash) DO NOTHING RETURNING id",
      [
        randomUUID(),
        user.id,
        tokenHash(`${user.id}:password-reset:${code}`, config.tokenPepper),
      ],
    );
    if (!inserted.rowCount) continue;
    return queueMail(client, config, user.id, "reset", {
      to: user.email_normalized,
      subject: "Reset your KYC password",
      text: `Your password reset code is ${code}. It expires in 10 minutes and can be used once. If you did not request this, ignore this email.`,
    });
  }
  throw new ApiError(
    503,
    "RESET_UNAVAILABLE",
    "Password reset is temporarily unavailable. Please try again shortly.",
  );
}
@Injectable()
export class AuthService implements OnModuleInit {
  private dummyPasswordHash!: string;

  constructor(
    @Inject(DATABASE_POOL) private readonly pool: Pool,
    @Inject(APP_CONFIG) private readonly config: Config,
    @Inject(MAILER) private readonly mailer: Mailer,
  ) {}

  async onModuleInit() {
    // Compute once before serving requests, including the unknown-account password path.
    this.dummyPasswordHash = await passwordHash(opaqueToken());
  }

  async register(dto: RegisterDto) {
    const { pool, config, mailer } = this;
    const { email, password } = dto;
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
    return { user: publicUser(result.user), nextStep: "VERIFY_EMAIL" };
  }

  async resendVerification(dto: EmailDto) {
    const { pool, config } = this;
    const { email } = dto;
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
  }

  async verifyEmail(dto: VerifyEmailDto) {
    const { pool, config } = this;
    const { email, code } = dto;
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
  }

  async login(dto: LoginDto) {
    const { pool, config, mailer } = this;
    const { email, password } = dto;
    const result = await transaction(pool, async (client) => {
      const users = await client.query(
        "SELECT * FROM users WHERE email_normalized=$1 FOR UPDATE",
        [email],
      );
      const user = users.rows[0];
      const passwordMatches = await argon2.verify(
        user?.password_hash ?? this.dummyPasswordHash,
        password,
      );
      if (!user || user.status === "disabled" || !passwordMatches)
        throw new ApiError(
          401,
          "INVALID_CREDENTIALS",
          "Unable to sign in with the provided credentials.",
        );
      if (!user.email_verified_at) {
        const recent = await client.query(
          "SELECT 1 FROM email_verification_tokens WHERE user_id=$1 AND created_at>now()-interval '30 seconds'",
          [user.id],
        );
        return {
          verificationMail: recent.rowCount
            ? null
            : await createOtp(client, user, config),
        };
      }
      return {
        session: sessionResponse(await issueSession(client, user, config)),
      };
    });
    if ("verificationMail" in result) {
      // Commit the OTP before returning the verification error, and retain
      // queued delivery for retry if SMTP is temporarily unavailable.
      if (result.verificationMail)
        await deliverQueued(pool, config, mailer, result.verificationMail.id);
      throw new ApiError(
        403,
        "EMAIL_NOT_VERIFIED",
        "Please verify your email before signing in.",
      );
    }
    return result.session;
  }

  async refresh(dto: RefreshDto) {
    const { pool, config } = this;
    const { refreshToken } = dto;
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
        "SELECT s.*,u.email_normalized,u.email_verified_at,u.role,u.status AS user_status FROM auth_sessions s JOIN users u ON u.id=s.user_id WHERE s.refresh_token_hash=$1 FOR UPDATE OF s",
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
  }

  async logout(dto: RefreshDto) {
    const { pool, config } = this;
    const { refreshToken } = dto;
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
  }

  async currentUser(userId: string) {
    const user = await this.pool.query("SELECT * FROM users WHERE id=$1", [
      userId,
    ]);
    return { user: publicUser(user.rows[0]) };
  }

  async forgotPassword(dto: EmailDto) {
    const { pool, config } = this;
    const { email } = dto;
    await transaction(pool, async (client) => {
      const users = await client.query(
        "SELECT * FROM users WHERE email_normalized=$1 AND status<>'disabled' FOR UPDATE",
        [email],
      );
      const user = users.rows[0];
      if (!user) return null;
      const recent = await client.query(
        "SELECT 1 FROM password_reset_tokens WHERE user_id=$1 AND created_at>now()-interval '30 seconds'",
        [user.id],
      );
      if (recent.rowCount) return null;
      return createResetOtp(client, user, config);
    });
    // Keep the response generic and independent of SMTP availability/latency.
    return genericMessage;
  }

  async resetPassword(dto: ResetPasswordDto) {
    const { pool, config } = this;
    const { email, code, newPassword } = dto;
    const hash = await passwordHash(newPassword);
    const result = await transaction(pool, async (client) => {
      // Match login/refresh/resend lock ordering so session revocation is atomic.
      const users = await client.query(
        "SELECT * FROM users WHERE email_normalized=$1 FOR UPDATE",
        [email],
      );
      const user = users.rows[0];
      if (!user || user.status === "disabled")
        return { error: "RESET_OTP_INVALID" } as const;
      const tokens = await client.query(
        "SELECT * FROM password_reset_tokens WHERE user_id=$1 AND consumed_at IS NULL ORDER BY created_at DESC LIMIT 1 FOR UPDATE",
        [user.id],
      );
      const reset = tokens.rows[0];
      if (!reset || reset.attempt_count >= 5)
        return { error: "RESET_OTP_INVALID" } as const;
      if (new Date(reset.expires_at).getTime() <= Date.now())
        return { error: "RESET_OTP_EXPIRED" } as const;
      const codeHash = tokenHash(
        `${user.id}:password-reset:${code}`,
        config.tokenPepper,
      );
      if (
        !timingSafeEqual(Buffer.from(codeHash), Buffer.from(reset.token_hash))
      ) {
        await client.query(
          "UPDATE password_reset_tokens SET attempt_count=attempt_count+1 WHERE id=$1",
          [reset.id],
        );
        // Return the error after committing so wrong-attempt counts persist.
        return { error: "RESET_OTP_INVALID" } as const;
      }
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
      await client.query(
        "DELETE FROM email_outbox WHERE user_id=$1 AND kind='reset'",
        [reset.user_id],
      );
      return { success: true } as const;
    });
    if ("error" in result)
      throw new ApiError(
        400,
        result.error!,
        result.error === "RESET_OTP_EXPIRED"
          ? "Your password reset code expired. Please request a new code."
          : "Invalid password reset code. Check the code or request a new one.",
      );
    return { success: true };
  }
}
