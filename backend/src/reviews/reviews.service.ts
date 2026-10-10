import { Inject, Injectable } from "@nestjs/common";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import type { Pool, PoolClient } from "pg";
import { requireRole, type UserRole } from "../auth/roles.js";
import type { Config } from "../config.js";
import { transaction } from "../database.js";
import { ApiError } from "../errors.js";
import { APP_CONFIG, DATABASE_POOL } from "../infrastructure/tokens.js";
import {
  getProfile,
  lockedProfile,
  reviewProfile,
  type MediaRecord,
} from "../kyc/kyc.repository.js";
import type { MediaKind } from "../kyc/kyc.schemas.js";
import { decrypt } from "../security.js";
import {
  archivedMedia,
  submissionHistory,
} from "../kyc/kyc-history.repository.js";
import type { HistoryPagination } from "../kyc/kyc-history.schemas.js";
import type { ReviewDecision, ReviewPagination } from "./reviews.schemas.js";

const reviewerRoles: UserRole[] = ["reviewer", "super_admin"];

@Injectable()
export class ReviewsService {
  constructor(
    @Inject(DATABASE_POOL) private readonly pool: Pool,
    @Inject(APP_CONFIG) private readonly config: Config,
  ) {}

  async queue(actorId: string, pagination: ReviewPagination) {
    return transaction(this.pool, async (client) => {
      await requireRole(client, actorId, reviewerRoles, true);
      const rows = await client.query<{
        user_id: string;
        email_normalized: string;
        status: "pending_review";
        submitted_at: Date;
      }>(
        "SELECT p.user_id,u.email_normalized,p.status,p.submitted_at FROM kyc_profiles p JOIN users u ON u.id=p.user_id WHERE p.status='pending_review' AND p.user_id<>$1 ORDER BY p.submitted_at ASC,p.user_id ASC LIMIT $2 OFFSET $3",
        [actorId, pagination.limit, pagination.offset],
      );
      const count = await client.query<{ total: string }>(
        "SELECT count(*) AS total FROM kyc_profiles WHERE status='pending_review' AND user_id<>$1",
        [actorId],
      );
      return {
        profiles: rows.rows.map((row) => ({
          userId: row.user_id,
          email: row.email_normalized,
          status: row.status,
          submittedAt: row.submitted_at?.toISOString() ?? null,
        })),
        total: Number(count.rows[0]!.total),
      };
    });
  }

  async detail(actorId: string, userId: string) {
    return transaction(this.pool, async (client) => {
      await this.pendingProfile(client, actorId, userId);
      const user = await client.query<{ id: string; email_normalized: string }>(
        "SELECT id,email_normalized FROM users WHERE id=$1",
        [userId],
      );
      return {
        user: { id: userId, email: user.rows[0]!.email_normalized },
        profile: await getProfile(client, userId, this.config),
      };
    });
  }

  async media(actorId: string, userId: string, kind: MediaKind) {
    return transaction(this.pool, async (client) => {
      await this.pendingProfile(client, actorId, userId);
      const rows = await client.query<MediaRecord>(
        "SELECT * FROM kyc_media WHERE user_id=$1 AND kind=$2",
        [userId, kind],
      );
      const record = rows.rows[0];
      if (!record)
        throw new ApiError(404, "MEDIA_NOT_FOUND", "Image not found.");
      return {
        data: decrypt(
          await readFile(join(this.config.mediaDir, record.storage_key)),
          this.config.mediaKey,
        ),
        mimeType: record.mime_type,
      };
    });
  }

  async decide(actorId: string, userId: string, decision: ReviewDecision) {
    const profile = await reviewProfile(
      this.pool,
      userId,
      decision.decision,
      decision.reason,
      decision.requiredSteps,
      actorId,
      this.config,
    );
    return { profile };
  }

  async history(
    actorId: string,
    userId: string,
    pagination: HistoryPagination,
  ) {
    return transaction(this.pool, async (client) => {
      await this.authorizedProfile(client, actorId, userId);
      return submissionHistory(client, userId, pagination, this.config);
    });
  }

  async historyMedia(
    actorId: string,
    userId: string,
    submissionId: string,
    kind: MediaKind,
  ) {
    return transaction(this.pool, async (client) => {
      await this.authorizedProfile(client, actorId, userId);
      return archivedMedia(client, userId, submissionId, kind, this.config);
    });
  }

  private async pendingProfile(
    client: PoolClient,
    actorId: string,
    userId: string,
  ) {
    const profile = await this.authorizedProfile(client, actorId, userId);
    if (profile.status !== "pending_review")
      throw new ApiError(
        404,
        "KYC_REVIEW_NOT_FOUND",
        "Pending profile not found.",
      );
    return profile;
  }

  private async authorizedProfile(
    client: PoolClient,
    actorId: string,
    userId: string,
  ) {
    await requireRole(client, actorId, reviewerRoles, true);
    if (actorId === userId)
      throw new ApiError(
        403,
        "SELF_REVIEW_FORBIDDEN",
        "You cannot review your own profile.",
      );
    return lockedProfile(client, userId);
  }
}
