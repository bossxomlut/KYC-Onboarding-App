import { Inject, Injectable } from "@nestjs/common";
import type { Pool, PoolClient } from "pg";
import { requireRole, type UserRole } from "../auth/roles.js";
import type { Config } from "../config.js";
import { transaction } from "../database.js";
import { ApiError } from "../errors.js";
import { APP_CONFIG, DATABASE_POOL } from "../infrastructure/tokens.js";
import { lockedProfile, reviewProfile } from "../kyc/kyc.repository.js";
import type { MediaKind } from "../kyc/kyc.schemas.js";
import {
  archivedMedia,
  ensureCurrentSubmission,
  submissionSnapshot,
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
      const statuses =
        pagination.status === "all"
          ? ["pending_review", "verified", "rejected"]
          : [pagination.status];
      const search = pagination.search
        ? `%${pagination.search.replace(/[\\%_]/g, "\\$&")}%`
        : null;
      const rows = await client.query<{
        user_id: string | null;
        email_normalized: string | null;
        status: "pending_review" | "verified" | "rejected" | null;
        submitted_at: Date | null;
        total: string;
      }>(
        `WITH filtered AS MATERIALIZED (
          SELECT p.user_id,u.email_normalized,p.status,p.submitted_at
          FROM kyc_profiles p JOIN users u ON u.id=p.user_id
          WHERE p.user_id<>$1 AND p.status=ANY($2::text[])
            AND ($3::text IS NULL OR u.email_normalized ILIKE $3 ESCAPE '\\')
        )
        SELECT page.*,counts.total
        FROM (SELECT count(*) AS total FROM filtered) counts
        LEFT JOIN LATERAL (
          SELECT * FROM filtered
          ORDER BY submitted_at ASC,user_id ASC LIMIT $4 OFFSET $5
        ) page ON true
        ORDER BY page.submitted_at ASC,page.user_id ASC`,
        [actorId, statuses, search, pagination.limit, pagination.offset],
      );
      return {
        profiles: rows.rows
          .filter((row) => row.user_id !== null)
          .map((row) => ({
            userId: row.user_id!,
            email: row.email_normalized!,
            status: row.status!,
            submittedAt: row.submitted_at?.toISOString() ?? null,
          })),
        total: Number(rows.rows[0]!.total),
      };
    });
  }

  async detail(actorId: string, userId: string) {
    return transaction(this.pool, async (client) => {
      await this.pendingProfile(client, actorId, userId);
      const submissionId = await ensureCurrentSubmission(client, userId);
      const user = await client.query<{ id: string; email_normalized: string }>(
        "SELECT id,email_normalized FROM users WHERE id=$1",
        [userId],
      );
      return {
        submissionId,
        user: { id: userId, email: user.rows[0]!.email_normalized },
        profile: await submissionSnapshot(
          client,
          userId,
          submissionId,
          this.config,
        ),
      };
    });
  }

  async media(
    actorId: string,
    userId: string,
    submissionId: string,
    kind: MediaKind,
  ) {
    return transaction(this.pool, async (client) => {
      await this.pendingProfile(client, actorId, userId);
      const currentId = await ensureCurrentSubmission(client, userId);
      if (currentId !== submissionId)
        throw new ApiError(
          409,
          "KYC_REVIEW_CHANGED",
          "This submission has changed. Reload it before reviewing its photos.",
        );
      return archivedMedia(client, userId, submissionId, kind, this.config);
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
      decision.submissionId,
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
