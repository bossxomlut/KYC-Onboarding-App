import { randomUUID } from "node:crypto";
import { Inject, Injectable } from "@nestjs/common";
import type { Pool, PoolClient } from "pg";
import type { Config } from "../config.js";
import { transaction } from "../database.js";
import { ApiError } from "../errors.js";
import { APP_CONFIG, DATABASE_POOL, MAILER } from "../infrastructure/tokens.js";
import { deliverQueued, type Mailer } from "../mail.js";
import { createOtp } from "../auth/auth.service.js";
import { passwordHash } from "../auth/password.js";
import { requireRole, type UserRole } from "../auth/roles.js";
import type {
  ChangeRoleDto,
  CreateAccountDto,
  DecideRoleDto,
  PaginationDto,
  RequestRoleDto,
  RequestsPaginationDto,
} from "./access.dto.js";

function publicUser(row: any) {
  return {
    id: row.id,
    email: row.email_normalized,
    emailVerified: row.email_verified_at !== null,
    role: row.role as UserRole,
    createdAt: row.created_at,
  };
}

function publicRequest(row: any) {
  return {
    id: row.id,
    userId: row.user_id,
    email: row.email_normalized,
    status: row.status,
    reason: row.reason,
    decisionReason: row.decision_reason,
    createdAt: row.created_at,
    decidedAt: row.decided_at,
  };
}

async function auditRole(
  client: PoolClient,
  actorId: string,
  targetUserId: string,
  previousRole: UserRole | null,
  newRole: UserRole,
  reason?: string,
) {
  await client.query(
    "INSERT INTO role_audit_events(id,actor_id,target_user_id,previous_role,new_role,reason) VALUES($1,$2,$3,$4,$5,$6)",
    [
      randomUUID(),
      actorId,
      targetUserId,
      previousRole,
      newRole,
      reason ?? null,
    ],
  );
}

function protectedAccount(user: any) {
  if (!user) throw new ApiError(404, "USER_NOT_FOUND", "Account not found.");
  if (user.role === "super_admin")
    throw new ApiError(
      403,
      "SUPER_ADMIN_PROTECTED",
      "The super admin account cannot be changed here.",
    );
  if (user.status === "disabled")
    throw new ApiError(409, "ACCOUNT_DISABLED", "This account is disabled.");
}

@Injectable()
export class AccessService {
  constructor(
    @Inject(DATABASE_POOL) private readonly pool: Pool,
    @Inject(APP_CONFIG) private readonly config: Config,
    @Inject(MAILER) private readonly mailer: Mailer,
  ) {}

  async listUsers(actorId: string, pagination: PaginationDto) {
    return transaction(this.pool, async (client) => {
      await requireRole(client, actorId, ["super_admin"], true);
      const [users, count] = await Promise.all([
        client.query(
          "SELECT id,email_normalized,email_verified_at,role,created_at FROM users ORDER BY created_at DESC,id LIMIT $1 OFFSET $2",
          [pagination.limit, pagination.offset],
        ),
        client.query("SELECT count(*)::integer AS total FROM users"),
      ]);
      return { users: users.rows.map(publicUser), total: count.rows[0].total };
    });
  }

  async createAccount(actorId: string, dto: CreateAccountDto) {
    const hash = await passwordHash(dto.password);
    const result = await transaction(this.pool, async (client) => {
      await requireRole(client, actorId, ["super_admin"], true);
      const insert = await client.query(
        "INSERT INTO users(id,email_normalized,password_hash,role) VALUES($1,$2,$3,$4) ON CONFLICT(email_normalized) DO NOTHING RETURNING *",
        [randomUUID(), dto.email, hash, dto.role],
      );
      const user = insert.rows[0];
      if (!user)
        throw new ApiError(
          409,
          "ACCOUNT_EXISTS",
          "An account already exists. Sign in or resend verification.",
        );
      await client.query("INSERT INTO kyc_profiles(id,user_id) VALUES($1,$2)", [
        randomUUID(),
        user.id,
      ]);
      await auditRole(
        client,
        actorId,
        user.id,
        null,
        dto.role,
        "Account created by super admin",
      );
      return { user, mail: await createOtp(client, user, this.config) };
    });
    if (
      !(await deliverQueued(
        this.pool,
        this.config,
        this.mailer,
        result.mail.id,
      ))
    )
      throw new ApiError(
        503,
        "EMAIL_DELIVERY_FAILED",
        "Email delivery is temporarily unavailable. The account was saved and the email is queued. Retry verification shortly.",
      );
    return { user: publicUser(result.user), nextStep: "VERIFY_EMAIL" };
  }

  async changeRole(actorId: string, userId: string, dto: ChangeRoleDto) {
    return transaction(this.pool, async (client) => {
      await requireRole(client, actorId, ["super_admin"], true);
      const target = (
        await client.query("SELECT * FROM users WHERE id=$1 FOR UPDATE", [
          userId,
        ])
      ).rows[0];
      protectedAccount(target);
      let user = target;
      if (target.role !== dto.role) {
        user = (
          await client.query(
            "UPDATE users SET role=$2,updated_at=now() WHERE id=$1 RETURNING *",
            [userId, dto.role],
          )
        ).rows[0];
        await auditRole(
          client,
          actorId,
          userId,
          target.role,
          dto.role,
          dto.reason,
        );
      }
      if (dto.role === "reviewer") {
        await client.query(
          "UPDATE role_requests SET status='approved',decision_reason=$2,decided_by=$3,decided_at=now() WHERE user_id=$1 AND status='pending'",
          [
            userId,
            dto.reason ?? "Reviewer permission granted directly",
            actorId,
          ],
        );
      }
      return { user: publicUser(user) };
    });
  }

  async ownRequest(userId: string) {
    await requireRole(this.pool, userId, ["user", "reviewer", "super_admin"]);
    const result = await this.pool.query(
      "SELECT r.*,u.email_normalized FROM role_requests r JOIN users u ON u.id=r.user_id WHERE r.user_id=$1 ORDER BY r.created_at DESC,r.id DESC LIMIT 1",
      [userId],
    );
    return { request: result.rows[0] ? publicRequest(result.rows[0]) : null };
  }

  async requestRole(userId: string, dto: RequestRoleDto) {
    try {
      return await transaction(this.pool, async (client) => {
        const user = await requireRole(
          client,
          userId,
          ["user", "reviewer", "super_admin"],
          true,
        );
        if (user.role !== "user")
          throw new ApiError(
            409,
            "ROLE_ALREADY_GRANTED",
            "This account already has reviewer permission.",
          );
        const request = (
          await client.query(
            "INSERT INTO role_requests(id,user_id,requested_role,reason) VALUES($1,$2,'reviewer',$3) RETURNING *",
            [randomUUID(), userId, dto.reason],
          )
        ).rows[0];
        return {
          request: publicRequest({
            ...request,
            email_normalized: user.email_normalized,
          }),
        };
      });
    } catch (error) {
      if ((error as { code?: string }).code === "23505")
        throw new ApiError(
          409,
          "ROLE_REQUEST_PENDING",
          "A reviewer permission request is already pending.",
        );
      throw error;
    }
  }

  async listRequests(actorId: string, pagination: RequestsPaginationDto) {
    return transaction(this.pool, async (client) => {
      await requireRole(client, actorId, ["super_admin"], true);
      const [requests, count] = await Promise.all([
        client.query(
          "SELECT r.*,u.email_normalized FROM role_requests r JOIN users u ON u.id=r.user_id WHERE r.status=$1 ORDER BY r.created_at ASC,r.id ASC LIMIT $2 OFFSET $3",
          [pagination.status, pagination.limit, pagination.offset],
        ),
        client.query(
          "SELECT count(*)::integer AS total FROM role_requests WHERE status=$1",
          [pagination.status],
        ),
      ]);
      return {
        requests: requests.rows.map(publicRequest),
        total: count.rows[0].total,
      };
    });
  }

  async decideRequest(actorId: string, requestId: string, dto: DecideRoleDto) {
    return transaction(this.pool, async (client) => {
      await requireRole(client, actorId, ["super_admin"], true);
      const owner = (
        await client.query("SELECT user_id FROM role_requests WHERE id=$1", [
          requestId,
        ])
      ).rows[0];
      if (!owner)
        throw new ApiError(
          404,
          "ROLE_REQUEST_NOT_FOUND",
          "Permission request not found.",
        );
      // Role mutations always lock the target account before its permission requests.
      const target = (
        await client.query("SELECT * FROM users WHERE id=$1 FOR UPDATE", [
          owner.user_id,
        ])
      ).rows[0];
      protectedAccount(target);
      const existing = (
        await client.query(
          "SELECT * FROM role_requests WHERE id=$1 FOR UPDATE",
          [requestId],
        )
      ).rows[0];
      if (existing.status !== "pending")
        throw new ApiError(
          409,
          "ROLE_REQUEST_RESOLVED",
          "This permission request has already been decided.",
        );
      let user = target;
      if (dto.decision === "approved" && target.role !== "reviewer") {
        user = (
          await client.query(
            "UPDATE users SET role='reviewer',updated_at=now() WHERE id=$1 RETURNING *",
            [target.id],
          )
        ).rows[0];
        await auditRole(
          client,
          actorId,
          target.id,
          target.role,
          "reviewer",
          dto.reason ?? "Reviewer permission request approved",
        );
      }
      const decided = (
        await client.query(
          "UPDATE role_requests SET status=$2,decision_reason=$3,decided_by=$4,decided_at=now() WHERE id=$1 RETURNING *",
          [requestId, dto.decision, dto.reason ?? null, actorId],
        )
      ).rows[0];
      return {
        request: publicRequest({
          ...decided,
          email_normalized: target.email_normalized,
        }),
        user: publicUser(user),
      };
    });
  }
}
