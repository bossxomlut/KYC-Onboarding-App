import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import { randomBytes, randomUUID } from "node:crypto";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import EmbeddedPostgres from "embedded-postgres";
import { Pool } from "pg";
import request from "supertest";
import { buildApp } from "../src/app.js";
import { migrate } from "../src/database.js";
import { passwordHash } from "../src/auth/password.js";
import type { Config } from "../src/config.js";
import { deliverQueued, type Mail } from "../src/mail.js";
import { decrypt, opaqueToken, tokenHash } from "../src/security.js";

let directory: string;
let postgres: EmbeddedPostgres;
let pool: Pool;
let app: Awaited<ReturnType<typeof buildApp>>;
let config: Config;
let initialHash: string;
let smtpCalls = 0;
const password = "SyntheticPass123!";
const replacement = "ReplacementPass456!";

before(async () => {
  directory = await mkdtemp(join(tmpdir(), "kyc-reset-otp-test-"));
  postgres = new EmbeddedPostgres({
    databaseDir: join(directory, "postgres"),
    port: 55446,
    user: "postgres",
    password: "test-only",
    persistent: false,
    initdbFlags: ["--encoding=UTF8"],
    onLog: () => {},
    onError: () => {},
  });
  await postgres.initialise();
  await postgres.start();
  pool = new Pool({
    connectionString:
      "postgresql://postgres:test-only@localhost:55446/postgres",
  });
  await migrate(pool);
  initialHash = await passwordHash(password);
  config = {
    nodeEnv: "test",
    host: "127.0.0.1",
    port: 0,
    databaseUrl: "unused",
    jwtSecret: randomBytes(32),
    tokenPepper: randomBytes(32),
    mediaKey: randomBytes(32),
    mediaDir: join(directory, "media"),
    smtpHost: "localhost",
    smtpPort: 1025,
    smtpSecure: false,
    mailFrom: "test@example.test",
    rateLimitMax: 1000,
    maxUploadBytes: 10 * 1024 * 1024,
  };
  app = await buildApp(config, pool, {
    send: async () => {
      smtpCalls++;
      throw new Error("Synthetic SMTP outage");
    },
  });
});

after(async () => {
  await app?.close();
  await pool?.end();
  await postgres?.stop();
  if (directory) await rm(directory, { recursive: true, force: true });
});

async function account(status = "active") {
  const id = randomUUID();
  const email = `${id}@example.test`;
  await pool.query(
    "INSERT INTO users(id,email_normalized,password_hash,email_verified_at,status) VALUES($1,$2,$3,now(),$4)",
    [id, email, initialHash, status],
  );
  return { id, email };
}

const post = (path: string, payload: unknown) =>
  request(app.getHttpServer()).post(`/api/v1/auth${path}`).send(payload);

async function queuedCode(user: Awaited<ReturnType<typeof account>>) {
  const response = await post("/password/forgot", { email: user.email });
  assert.equal(response.status, 200);
  const queue = await pool.query(
    "SELECT * FROM email_outbox WHERE user_id=$1 AND kind='reset'",
    [user.id],
  );
  assert.equal(queue.rowCount, 1);
  const row = queue.rows[0];
  const mail = JSON.parse(
    decrypt(
      Buffer.from(row.encrypted_payload, "base64"),
      config.mediaKey,
    ).toString(),
  ) as Mail;
  const code = mail.text.match(/\b\d{6}\b/)?.[0];
  assert.ok(code, "Reset email must contain a six-digit OTP.");
  return { code, mail, row };
}

test("password reset accepts email and six digits and rejects legacy token payloads", async () => {
  const user = await account();
  for (const payload of [
    { token: opaqueToken(), newPassword: replacement },
    { email: user.email, code: "12345", newPassword: replacement },
    { email: user.email, code: "1234567", newPassword: replacement },
    { email: user.email, code: "abcdef", newPassword: replacement },
    { email: user.email, code: "123456", newPassword: "short" },
  ]) {
    const response = await post("/password/reset", payload);
    assert.equal(response.status, 400);
    assert.equal(response.body.error.code, "VALIDATION_ERROR");
  }
  const accepted = await post("/password/reset", {
    email: user.email.toUpperCase(),
    code: "123456",
    newPassword: replacement,
  });
  assert.equal(accepted.body.error.code, "RESET_OTP_INVALID");
});

test("forgot password is generic, async, encrypted and has a ten-minute code lifetime", async () => {
  const user = await account();
  const disabled = await account("disabled");
  const initialCalls = smtpCalls;
  const known = await post("/password/forgot", { email: user.email });
  const unknown = await post("/password/forgot", {
    email: "unknown@example.test",
  });
  const blocked = await post("/password/forgot", { email: disabled.email });
  assert.equal(known.status, 200);
  assert.deepEqual(known.body, unknown.body);
  assert.deepEqual(known.body, blocked.body);
  assert.equal(smtpCalls, initialCalls);
  const { code, mail, row } = await queuedCode(user);
  assert.equal(mail.to, user.email);
  assert.ok(mail.text.includes("10 minutes"));
  assert.equal(/token=|https?:\/\/|kycapp:/.test(mail.text), false);
  assert.equal(row.encrypted_payload.includes(user.email), false);
  assert.equal(row.encrypted_payload.includes(code), false);
  const stored = await pool.query(
    "SELECT * FROM password_reset_tokens WHERE user_id=$1",
    [user.id],
  );
  assert.equal(stored.rowCount, 1);
  const token = stored.rows[0];
  assert.equal(
    token.token_hash,
    tokenHash(`${user.id}:password-reset:${code}`, config.tokenPepper),
  );
  assert.notEqual(token.token_hash, tokenHash(code, config.tokenPepper));
  assert.equal(token.attempt_count, 0);
  assert.equal(token.expires_at.getTime() - token.created_at.getTime(), 600000);
  assert.equal(row.expires_at.getTime() - row.created_at.getTime(), 600000);
  assert.equal(
    (
      await pool.query("SELECT 1 FROM password_reset_tokens WHERE user_id=$1", [
        disabled.id,
      ])
    ).rowCount,
    0,
  );
});

test("concurrent forgot requests share the account cooldown and keep only one queued code", async () => {
  const user = await account();
  const results = await Promise.all(
    Array.from({ length: 4 }, () =>
      post("/password/forgot", { email: user.email }),
    ),
  );
  assert.ok(results.every((result) => result.status === 200));
  assert.equal(
    (
      await pool.query("SELECT 1 FROM password_reset_tokens WHERE user_id=$1", [
        user.id,
      ])
    ).rowCount,
    1,
  );
  assert.equal(
    (
      await pool.query(
        "SELECT 1 FROM email_outbox WHERE user_id=$1 AND kind='reset'",
        [user.id],
      )
    ).rowCount,
    1,
  );
});

test("resending replaces the queued email and invalidates the previous reset code", async () => {
  const user = await account();
  const first = await queuedCode(user);
  await pool.query(
    "UPDATE password_reset_tokens SET created_at=now()-interval '31 seconds' WHERE user_id=$1",
    [user.id],
  );
  const next = await queuedCode(user);
  assert.notEqual(next.row.id, first.row.id);
  assert.notEqual(next.code, first.code);
  assert.equal(
    await deliverQueued(
      pool,
      config,
      { send: async () => assert.fail("Old mail must not be sent") },
      first.row.id,
    ),
    false,
  );
  const stale = await post("/password/reset", {
    email: user.email,
    code: first.code,
    newPassword: replacement,
  });
  assert.equal(stale.body.error.code, "RESET_OTP_INVALID");
  const current = await post("/password/reset", {
    email: user.email,
    code: next.code,
    newPassword: replacement,
  });
  assert.equal(current.status, 200);
});

test("reset persists at most five wrong attempts even when attempts race", async () => {
  const user = await account();
  const { code } = await queuedCode(user);
  const responses = await Promise.all(
    Array.from({ length: 7 }, () =>
      post("/password/reset", {
        email: user.email,
        code: "000000",
        newPassword: replacement,
      }),
    ),
  );
  assert.ok(
    responses.every(
      (response) => response.body.error.code === "RESET_OTP_INVALID",
    ),
  );
  const correct = await post("/password/reset", {
    email: user.email,
    code,
    newPassword: replacement,
  });
  assert.equal(correct.body.error.code, "RESET_OTP_INVALID");
  const persisted = await pool.query(
    "SELECT attempt_count FROM password_reset_tokens WHERE user_id=$1",
    [user.id],
  );
  assert.equal(persisted.rows[0].attempt_count, 5);
  assert.equal(
    (await post("/login", { email: user.email, password })).status,
    200,
  );
});

test("reset rejects expired codes, unknown accounts and accounts disabled after requesting", async () => {
  const user = await account();
  const { code } = await queuedCode(user);
  await pool.query(
    "UPDATE password_reset_tokens SET expires_at=now()-interval '1 second' WHERE user_id=$1",
    [user.id],
  );
  const expired = await post("/password/reset", {
    email: user.email,
    code,
    newPassword: replacement,
  });
  assert.equal(expired.body.error.code, "RESET_OTP_EXPIRED");
  await pool.query(
    "UPDATE password_reset_tokens SET expires_at=now()+interval '10 minutes' WHERE user_id=$1",
    [user.id],
  );
  await pool.query("UPDATE users SET status='disabled' WHERE id=$1", [user.id]);
  for (const email of [user.email, "missing@example.test"]) {
    const denied = await post("/password/reset", {
      email,
      code,
      newPassword: replacement,
    });
    assert.equal(denied.body.error.code, "RESET_OTP_INVALID");
  }
  assert.equal(
    (await pool.query("SELECT password_hash FROM users WHERE id=$1", [user.id]))
      .rows[0].password_hash,
    initialHash,
  );
});

test("reset hashes bind codes to the account and reset purpose and reject old link hashes", async () => {
  const user = await account();
  const code = "123456";
  for (const storedHash of [
    tokenHash(`${randomUUID()}:password-reset:${code}`, config.tokenPepper),
    tokenHash(`${user.id}:${code}`, config.tokenPepper),
    tokenHash(code, config.tokenPepper),
  ]) {
    await pool.query("DELETE FROM password_reset_tokens WHERE user_id=$1", [
      user.id,
    ]);
    await pool.query(
      "INSERT INTO password_reset_tokens(id,user_id,token_hash,expires_at) VALUES($1,$2,$3,now()+interval '10 minutes')",
      [randomUUID(), user.id, storedHash],
    );
    const response = await post("/password/reset", {
      email: user.email,
      code,
      newPassword: replacement,
    });
    assert.equal(response.body.error.code, "RESET_OTP_INVALID");
  }
});

test("a reset code is single-use, deletes queued reset mail and revokes every session", async () => {
  const user = await account();
  const sessions = await Promise.all([
    post("/login", { email: user.email, password }),
    post("/login", { email: user.email, password }),
  ]);
  const { code } = await queuedCode(user);
  const reset = await post("/password/reset", {
    email: user.email,
    code,
    newPassword: replacement,
  });
  assert.equal(reset.status, 200);
  assert.deepEqual(reset.body, { success: true });
  assert.equal(
    (
      await post("/password/reset", {
        email: user.email,
        code,
        newPassword: password,
      })
    ).body.error.code,
    "RESET_OTP_INVALID",
  );
  assert.equal(
    (
      await pool.query(
        "SELECT 1 FROM email_outbox WHERE user_id=$1 AND kind='reset'",
        [user.id],
      )
    ).rowCount,
    0,
  );
  assert.equal(
    (
      await pool.query(
        "SELECT 1 FROM auth_sessions WHERE user_id=$1 AND revoked_at IS NULL",
        [user.id],
      )
    ).rowCount,
    0,
  );
  for (const { body } of sessions) {
    const me = await request(app.getHttpServer())
      .get("/api/v1/auth/me")
      .set("Authorization", `Bearer ${body.accessToken}`);
    assert.equal(me.status, 401);
    assert.equal(
      (await post("/refresh", { refreshToken: body.refreshToken })).status,
      401,
    );
  }
  assert.equal(
    (await post("/login", { email: user.email, password })).status,
    401,
  );
  assert.equal(
    (await post("/login", { email: user.email, password: replacement })).status,
    200,
  );
});

test("concurrent reset and refresh leave no valid pre-reset sessions", async () => {
  const user = await account();
  const session = (await post("/login", { email: user.email, password })).body;
  const { code } = await queuedCode(user);
  const [first, second, refreshed] = await Promise.all([
    post("/password/reset", {
      email: user.email,
      code,
      newPassword: replacement,
    }),
    post("/password/reset", {
      email: user.email,
      code,
      newPassword: replacement,
    }),
    post("/refresh", { refreshToken: session.refreshToken }),
  ]);
  assert.deepEqual([first.status, second.status].sort(), [200, 400]);
  assert.ok([200, 401].includes(refreshed.status));
  assert.equal(
    (
      await pool.query(
        "SELECT 1 FROM auth_sessions WHERE user_id=$1 AND revoked_at IS NULL",
        [user.id],
      )
    ).rowCount,
    0,
  );
  assert.equal(
    (
      await post("/refresh", {
        refreshToken: refreshed.body.refreshToken ?? session.refreshToken,
      })
    ).status,
    401,
  );
});

test("OTP migration invalidates legacy link tokens and queued reset emails only", async () => {
  const user = await account();
  const tokenId = randomUUID();
  await pool.query(
    "INSERT INTO password_reset_tokens(id,user_id,token_hash,expires_at) VALUES($1,$2,$3,now()+interval '30 minutes')",
    [tokenId, user.id, tokenHash(opaqueToken(), config.tokenPepper)],
  );
  for (const kind of ["reset", "verification"]) {
    await pool.query(
      "INSERT INTO email_outbox(id,user_id,kind,encrypted_payload,expires_at) VALUES($1,$2,$3,'test-only',now()+interval '10 minutes')",
      [randomUUID(), user.id, kind],
    );
  }
  // Exercise upgrading an existing reset table independently of the clean migration path.
  await pool.query(
    "ALTER TABLE password_reset_tokens DROP COLUMN attempt_count",
  );
  await pool.query("DROP INDEX IF EXISTS password_reset_user_idx");
  await pool.query(
    await readFile(
      new URL("../migrations/007_password_reset_otp.sql", import.meta.url),
      "utf8",
    ),
  );
  const token = (
    await pool.query(
      "SELECT consumed_at,attempt_count FROM password_reset_tokens WHERE id=$1",
      [tokenId],
    )
  ).rows[0];
  assert.notEqual(token.consumed_at, null);
  assert.equal(token.attempt_count, 0);
  const queue = await pool.query(
    "SELECT kind FROM email_outbox WHERE user_id=$1",
    [user.id],
  );
  assert.deepEqual(
    queue.rows.map((row) => row.kind),
    ["verification"],
  );
});
