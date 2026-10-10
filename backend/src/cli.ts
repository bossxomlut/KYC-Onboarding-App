import { randomUUID } from "node:crypto";
import { parseArgs } from "node:util";
import { z } from "zod";
import { loadConfig } from "./config.js";
import { createPool, migrate, transaction } from "./database.js";
import { passwordHash } from "./auth/password.js";
import { reviewProfile } from "./kyc/kyc.repository.js";

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
    case "review": {
      let id = values.user;
      if (values.email) {
        const result = await pool.query(
          "SELECT id FROM users WHERE email_normalized=$1",
          [values.email.trim().toLowerCase()],
        );
        id = result.rows[0]?.id;
      }
      if (!id) throw new Error("Provide --user UUID or --email EMAIL.");
      const status = z.enum(["verified", "rejected"]).parse(values.status);
      await reviewProfile(
        pool,
        id,
        status,
        values.reason,
        values.steps?.split(",") ?? [],
      );
      console.log(`Review saved: ${status}.`);
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
        "Usage: npm run migrate | npm run demo | npm run review -- --email EMAIL --status verified|rejected [--reason REASON --steps selfie,document,personal_details]",
      );
  }
} catch (error) {
  console.error(error instanceof Error ? error.message : "Command failed.");
  process.exitCode = 1;
} finally {
  await pool.end();
}
