import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import EmbeddedPostgres from "embedded-postgres";
import { Pool } from "pg";
import { decrypt, encrypt } from "../src/security.js";

test("history migration preserves only the available legacy submission and known review attribution", async () => {
  const migration = await readFile(
    new URL("../migrations/005_kyc_submission_history.sql", import.meta.url),
    "utf8",
  );
  const directory = await mkdtemp(join(tmpdir(), "kyc-history-migration-"));
  const postgres = new EmbeddedPostgres({
    databaseDir: join(directory, "postgres"),
    port: 55443,
    user: "postgres",
    password: "test-only",
    persistent: false,
    initdbFlags: ["--encoding=UTF8"],
    onLog: () => {},
    onError: () => {},
  });
  let pool: Pool | undefined;
  try {
    await postgres.initialise();
    await postgres.start();
    pool = new Pool({
      connectionString:
        "postgresql://postgres:test-only@localhost:55443/postgres",
    });
    for (const name of [
      "001_initial.sql",
      "002_email_outbox.sql",
      "003_media_capture_id.sql",
      "004_account_roles.sql",
    ]) {
      await pool.query(
        await readFile(
          new URL(`../migrations/${name}`, import.meta.url),
          "utf8",
        ),
      );
    }
    const applicant = randomUUID();
    const actor = randomUUID();
    const profileId = randomUUID();
    const key = randomBytes(32);
    const details = {
      fullName: "Synthetic legacy applicant",
      documentNumber: "LEGACY123",
    };
    const encrypted = encrypt(
      Buffer.from(JSON.stringify(details)),
      key,
    ).toString("base64");
    for (const [id, role] of [
      [applicant, "user"],
      [actor, "reviewer"],
    ]) {
      await pool.query(
        "INSERT INTO users(id,email_normalized,password_hash,email_verified_at,status,role) VALUES($1,$2,'test-only',now(),'active',$3)",
        [id, `${id}@example.test`, role],
      );
    }
    await pool.query(
      "INSERT INTO kyc_profiles(id,user_id,status,personal_details,rejection_reason,required_steps,submitted_at,updated_at) VALUES($1,$2,'rejected',$3,'Legacy selfie needs retaking',ARRAY['selfie'],'2026-01-02T00:00:00Z','2026-01-03T00:00:00Z')",
      [profileId, applicant, encrypted],
    );
    for (const [time, decision] of [
      ["2026-01-01T00:00:00Z", "verified"],
      ["2026-01-03T00:00:00Z", "rejected"],
    ]) {
      await pool.query(
        "INSERT INTO kyc_reviews(id,user_id,decision,required_steps,created_at,reviewed_by) VALUES($1,$2,$3,ARRAY['selfie'],$4,$5)",
        [randomUUID(), applicant, decision, time, actor],
      );
    }
    const storageKeys: string[] = [];
    for (const kind of ["document", "selfie"]) {
      const storageKey = randomUUID();
      storageKeys.push(storageKey);
      await pool.query(
        "INSERT INTO kyc_media(id,user_id,kind,document_type,mime_type,size,storage_key,client_capture_id) VALUES($1,$2,$3,$4,'image/jpeg',123,$5,$6)",
        [
          randomUUID(),
          applicant,
          kind,
          kind === "document" ? "passport" : null,
          storageKey,
          `legacy-capture-${kind}`,
        ],
      );
    }
    await pool.query(migration);
    const rows = await pool.query(
      "SELECT * FROM kyc_submissions WHERE user_id=$1",
      [applicant],
    );
    assert.equal(
      rows.rowCount,
      1,
      "Unavailable earlier photos/details must not be invented from old review events.",
    );
    const archived = rows.rows[0];
    assert.equal(archived.version, 1);
    assert.equal(archived.profile_id, profileId);
    assert.equal(archived.status, "rejected");
    assert.deepEqual(
      JSON.parse(
        decrypt(
          Buffer.from(archived.personal_details, "base64"),
          key,
        ).toString(),
      ),
      details,
    );
    assert.equal(archived.reviewed_by, actor);
    assert.equal(
      archived.reviewer_email,
      null,
      "Historical email was not recorded by the old audit.",
    );
    assert.equal(
      archived.reviewer_role,
      null,
      "Historical role was not recorded by the old audit.",
    );
    assert.equal(
      archived.reviewed_at.toISOString(),
      "2026-01-03T00:00:00.000Z",
    );
    assert.equal(archived.review_reason, "Legacy selfie needs retaking");
    const media = await pool.query(
      "SELECT storage_key FROM kyc_submission_media WHERE submission_id=$1 ORDER BY kind",
      [archived.id],
    );
    assert.deepEqual(
      media.rows.map((row) => row.storage_key),
      storageKeys,
    );
    const current = await pool.query(
      "SELECT current_submission_id FROM kyc_profiles WHERE user_id=$1",
      [applicant],
    );
    assert.equal(current.rows[0].current_submission_id, archived.id);
  } finally {
    await pool?.end();
    await postgres.stop();
    await rm(directory, { recursive: true, force: true });
  }
});
