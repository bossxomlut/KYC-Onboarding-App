import { randomBytes, randomUUID } from "node:crypto";
import { mkdir, writeFile, unlink } from "node:fs/promises";
import { resolve } from "node:path";
import { parseArgs } from "node:util";
import { loadConfig } from "./config.js";
import { createPool, migrate, transaction } from "./database.js";
import { passwordHash } from "./auth/password.js";
import { bootstrapSuperAdmin } from "./auth/bootstrap-admin.js";

const config = loadConfig();
const pool = createPool(config.databaseUrl);
const { positionals, values } = parseArgs({
  allowPositionals: true,
  options: {
    user: { type: "string" },
    email: { type: "string" },
    status: { type: "string" },
    reason: { type: "string" },
    steps: { type: "string" },
  },
});
try {
  switch (positionals[0]) {
    case "migrate":
      await migrate(pool);
      console.log("Database migrations applied.");
      break;
    case "review":
      throw new Error(
        "Direct database reviews have been removed. Sign in to the app as a reviewer or super admin and open Review profiles.",
      );
    case "admin:bootstrap": {
      const production = config.nodeEnv === "production";
      const email =
        values.email ??
        process.env.BOOTSTRAP_ADMIN_EMAIL ??
        (production ? undefined : "superadmin@kyc.example");
      if (!email || (production && !process.env.BOOTSTRAP_ADMIN_PASSWORD))
        throw new Error(
          "Production bootstrap requires BOOTSTRAP_ADMIN_EMAIL and BOOTSTRAP_ADMIN_PASSWORD supplied securely by the operator.",
        );
      const password =
        process.env.BOOTSTRAP_ADMIN_PASSWORD ??
        `Aa1!${randomBytes(32).toString("base64url")}`;
      const credentialsPath = resolve(".local/super-admin.json");
      let credentialFileCreated = false;
      try {
        // Persist the generated credential before committing its account, so a
        // filesystem failure cannot leave an owner with an unknown password.
        if (!production) {
          const existing = await pool.query(
            "SELECT 1 FROM users WHERE role='super_admin'",
          );
          if (!existing.rowCount) {
            await mkdir(resolve(".local"), { recursive: true, mode: 0o700 });
            await writeFile(
              credentialsPath,
              JSON.stringify(
                { email: email.trim().toLowerCase(), password },
                null,
                2,
              ) + "\n",
              { mode: 0o600, flag: "wx" },
            );
            credentialFileCreated = true;
          }
        }
        const result = await bootstrapSuperAdmin(pool, email, password);
        if (result.created)
          console.log(
            production
              ? "Super admin created. Use the credentials supplied by the operator."
              : `Super admin created. Local credentials: ${credentialsPath}`,
          );
        else {
          if (credentialFileCreated) await unlink(credentialsPath);
          console.log(
            "Super admin already exists; credentials and roles were preserved.",
          );
        }
      } catch (error) {
        if (credentialFileCreated) await unlink(credentialsPath);
        throw error;
      }
      break;
    }
    case "demo": {
      if (config.nodeEnv === "production")
        throw new Error("Demo seeding is disabled in production.");
      const hash = await passwordHash("DemoOnlyPass123!");
      await transaction(pool, async (client) => {
        const user = await client.query(
          "INSERT INTO users(id,email_normalized,password_hash,email_verified_at,status) VALUES($1,$2,$3,now(),'active') ON CONFLICT(email_normalized) DO NOTHING RETURNING id",
          [randomUUID(), "demo@kyc.example", hash],
        );
        if (user.rowCount)
          await client.query(
            "INSERT INTO kyc_profiles(id,user_id) VALUES($1,$2)",
            [randomUUID(), user.rows[0].id],
          );
      });
      console.log(
        "Synthetic demo account is ready. Credentials are documented in docs/backend.md.",
      );
      break;
    }
    default:
      throw new Error(
        "Usage: npm run migrate | npm run demo | npm run admin:bootstrap [-- --email EMAIL]",
      );
  }
} catch (error) {
  console.error(error instanceof Error ? error.message : "Command failed.");
  process.exitCode = 1;
} finally {
  await pool.end();
}
