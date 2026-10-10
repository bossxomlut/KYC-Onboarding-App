/** Test-only privileged coordinator. The mobile app never calls this script. */
import { loadConfig } from "../backend/src/config.js";
import { createPool } from "../backend/src/database.js";
import { reviewProfile } from "../backend/src/kyc/kyc.repository.js";
import { passwordHash } from "../backend/src/auth/password.js";
import { randomBytes, randomUUID } from "node:crypto";
const email = process.argv[2];
const config = loadConfig();
if (!email?.endsWith("@kyc.example") || config.nodeEnv === "production") {
  throw new Error(
    "The demo coordinator requires a synthetic @kyc.example account in development.",
  );
}
const pool = createPool(config.databaseUrl);
let reviews = 0;
const deadline = Date.now() + 600_000;
try {
  const reviewerEmail = "demo-reviewer@kyc.example";
  const reviewerHash = await passwordHash(
    `Aa1!${randomBytes(32).toString("base64url")}`,
  );
  const reviewer = await pool.query(
    "INSERT INTO users(id,email_normalized,password_hash,email_verified_at,status,role) VALUES($1,$2,$3,now(),'active','reviewer') ON CONFLICT(email_normalized) DO NOTHING RETURNING id",
    [randomUUID(), reviewerEmail, reviewerHash],
  );
  const existingReviewer = reviewer.rowCount
    ? reviewer
    : await pool.query(
        "SELECT id FROM users WHERE email_normalized=$1 AND role='reviewer' AND status='active' AND email_verified_at IS NOT NULL",
        [reviewerEmail],
      );
  const reviewerId = existingReviewer.rows[0]?.id;
  if (!reviewerId)
    throw new Error(
      "The synthetic demo reviewer account exists without the required role.",
    );
  while (reviews < 2 && Date.now() < deadline) {
    const records = await pool.query(
      "SELECT p.status,u.id FROM kyc_profiles p JOIN users u ON p.user_id=u.id WHERE u.email_normalized=$1",
      [email],
    );
    const profile = records.rows[0];
    if (profile?.status === "pending_review") {
      await new Promise((resolve) => setTimeout(resolve, 3000));
      await reviewProfile(
        pool,
        profile.id,
        reviews === 0 ? "rejected" : "verified",
        reviews === 0
          ? "Please retake your demo selfie in better light."
          : undefined,
        reviews === 0 ? ["selfie"] : [],
        reviewerId,
      );
      reviews++;
      console.log(
        `Demo reviewer recorded ${reviews === 1 ? "rejected" : "verified"}.`,
      );
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  if (reviews !== 2) throw new Error("Demo timed out before two submissions.");
} finally {
  await pool.end();
}
