import {
  Inject,
  Injectable,
  type CanActivate,
  type ExecutionContext,
} from "@nestjs/common";
import type { Request } from "express";
import type { Pool } from "pg";
import type { Config } from "../config.js";
import { ApiError } from "../errors.js";
import { APP_CONFIG, DATABASE_POOL } from "../infrastructure/tokens.js";
import { verifyAccess } from "../security.js";

export interface AuthenticatedRequest extends Request {
  userId: string;
}

@Injectable()
export class AuthenticationGuard implements CanActivate {
  constructor(
    @Inject(DATABASE_POOL) private readonly pool: Pool,
    @Inject(APP_CONFIG) private readonly config: Config,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const header = request.headers.authorization;
    if (!header?.startsWith("Bearer "))
      throw new ApiError(401, "SESSION_EXPIRED", "Please sign in to continue.");
    let claims: { userId: string; sessionId: string };
    try {
      claims = await verifyAccess(header.substring(7), this.config);
    } catch {
      throw new ApiError(
        401,
        "SESSION_EXPIRED",
        "Your session has expired. Please sign in again.",
      );
    }
    const active = await this.pool.query(
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
    return true;
  }
}
