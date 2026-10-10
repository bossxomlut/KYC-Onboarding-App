import { randomUUID } from "node:crypto";
import type { Pool } from "pg";
import { transaction } from "../database.js";
import { ApiError } from "../errors.js";
import { passwordHash } from "./password.js";
import { registerSchema } from "./auth.dto.js";

/** Operator-only bootstrap. It never promotes an existing self-registered account
 * and never resets an owner's credentials on subsequent invocations. */
export async function bootstrapSuperAdmin(
  pool: Pool,
  email: string,
  password: string,
) {
  const credentials = registerSchema.parse({ email, password });
  const hash = await passwordHash(credentials.password);
  return transaction(pool, async (client) => {
    await client.query("SELECT pg_advisory_xact_lock(784325192)");
    const existing = await client.query(
      "SELECT id,email_normalized FROM users WHERE role='super_admin'",
    );
    if (existing.rowCount) {
      if (existing.rows[0].email_normalized !== credentials.email)
        throw new ApiError(
          409,
          "SUPER_ADMIN_EXISTS",
          "A super admin already exists. Use the original bootstrap email.",
        );
      return { created: false, userId: existing.rows[0].id as string };
    }
    const collision = await client.query(
      "SELECT 1 FROM users WHERE email_normalized=$1",
      [credentials.email],
    );
    if (collision.rowCount)
      throw new ApiError(
        409,
        "ACCOUNT_EXISTS",
        "Choose an unused bootstrap email. Existing accounts are never promoted by bootstrap.",
      );
    const id = randomUUID();
    await client.query(
      "INSERT INTO users(id,email_normalized,password_hash,email_verified_at,status,role) VALUES($1,$2,$3,now(),'active','super_admin')",
      [id, credentials.email, hash],
    );
    await client.query("INSERT INTO kyc_profiles(id,user_id) VALUES($1,$2)", [
      randomUUID(),
      id,
    ]);
    await client.query(
      "INSERT INTO role_audit_events(id,actor_id,target_user_id,previous_role,new_role,reason) VALUES($1,$2,$2,NULL,'super_admin','Initial operator bootstrap')",
      [randomUUID(), id],
    );
    return { created: true, userId: id };
  });
}
