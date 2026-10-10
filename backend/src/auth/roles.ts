import {
  Injectable,
  Inject,
  SetMetadata,
  type CanActivate,
  type ExecutionContext,
} from "@nestjs/common";
import { Reflector } from "@nestjs/core";
import type { Pool, PoolClient } from "pg";
import { ApiError } from "../errors.js";
import type { AuthenticatedRequest } from "./authentication.guard.js";

export type UserRole = "user" | "reviewer" | "super_admin";
const ROLE_METADATA = "account:allowed-roles";
export const Roles = (...roles: UserRole[]) =>
  SetMetadata(ROLE_METADATA, roles);

/** Check the live role again inside a privileged transaction. The share lock
 * prevents revocation from interleaving with an authorized decision. */
export async function requireRole(
  client: Pool | PoolClient,
  actorId: string,
  allowedRoles: readonly UserRole[],
  lock = false,
) {
  const result = await client.query(
    `SELECT * FROM users WHERE id=$1${lock ? " FOR SHARE" : ""}`,
    [actorId],
  );
  const actor = result.rows[0];
  if (
    !actor ||
    actor.status !== "active" ||
    !actor.email_verified_at ||
    !allowedRoles.includes(actor.role)
  )
    throw new ApiError(
      403,
      "FORBIDDEN",
      "You do not have permission for this action.",
    );
  return actor;
}

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(@Inject(Reflector) private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const roles = this.reflector.getAllAndOverride<UserRole[]>(ROLE_METADATA, [
      context.getHandler(),
      context.getClass(),
    ]);
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    // Guard usage without an explicit policy is denied by default.
    if (!roles?.includes(request.userRole))
      throw new ApiError(
        403,
        "FORBIDDEN",
        "You do not have permission for this action.",
      );
    return true;
  }
}
