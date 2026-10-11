import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { randomBytes, randomUUID } from "node:crypto";
import EmbeddedPostgres from "embedded-postgres";
import { Pool } from "pg";
import request from "supertest";
import { buildApp } from "../src/app.js";
import { migrate } from "../src/database.js";
import { passwordHash } from "../src/auth/password.js";
import type { Config } from "../src/config.js";
import type { Mail } from "../src/mail.js";

let directory: string;
let postgres: EmbeddedPostgres;
let pool: Pool;
let app: Awaited<ReturnType<typeof buildApp>>;
let config: Config;
const mails: Mail[] = [];
const password = "SyntheticAccess123!";
type Session = {
  accessToken: string;
  refreshToken: string;
  user: { id: string; role: string };
};
let admin: Session;

before(async () => {
  directory = await mkdtemp(join(tmpdir(), "kyc-access-test-"));
  postgres = new EmbeddedPostgres({
    databaseDir: join(directory, "postgres"),
    port: 55440,
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
      "postgresql://postgres:test-only@localhost:55440/postgres",
  });
  await migrate(pool);
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
    send: async (mail) => {
      mails.push(mail);
    },
  });
});

after(async () => {
  await app?.close();
  await pool?.end();
  await postgres?.stop();
  if (directory) await rm(directory, { recursive: true, force: true });
});

async function json(
  method: "get" | "post" | "put",
  path: string,
  body?: unknown,
  token?: string,
  application = app,
) {
  let call = request(application.getHttpServer())[method](`/api/v1${path}`);
  if (token) call = call.set("authorization", `Bearer ${token}`);
  if (body !== undefined) call = call.send(body as object);
  return call;
}

async function verify(email: string): Promise<Session> {
  const code = mails
    .findLast((mail) => mail.to === email)!
    .text.match(/\b\d{6}\b/)![0];
  const response = await json("post", "/auth/email/verify", { email, code });
  assert.equal(response.status, 200);
  return response.body;
}

async function register(email: string): Promise<Session> {
  const response = await json("post", "/auth/register", { email, password });
  assert.equal(response.status, 201);
  return verify(email);
}

async function seedAdmin() {
  if (admin) return admin;
  const id = randomUUID();
  await pool.query(
    "INSERT INTO users(id,email_normalized,password_hash,role,status,email_verified_at) VALUES($1,'root-access@example.test',$2,'super_admin','active',now())",
    [id, await passwordHash(password)],
  );
  await pool.query("INSERT INTO kyc_profiles(id,user_id) VALUES($1,$2)", [
    randomUUID(),
    id,
  ]);
  const response = await json("post", "/auth/login", {
    email: "root-access@example.test",
    password,
  });
  assert.equal(response.status, 200);
  admin = response.body;
  return admin;
}

test("public registration cannot choose roles and normal users cannot access administration", async () => {
  const forged = await json("post", "/auth/register", {
    email: "forged-access@example.test",
    password,
    role: "super_admin",
  });
  assert.equal(forged.status, 400);
  const user = await register("plain-access@example.test");
  assert.equal(user.user.role, "user");
  assert.equal((await json("get", "/admin/users")).status, 401);
  assert.equal(
    (await json("get", "/admin/users", undefined, user.accessToken)).status,
    403,
  );
  assert.equal(
    (await json("get", "/admin/role-requests", undefined, user.accessToken))
      .status,
    403,
  );
  assert.equal(
    (
      await json(
        "post",
        "/admin/users",
        { email: "forged-created@example.test", password, role: "reviewer" },
        user.accessToken,
      )
    ).status,
    403,
  );
  assert.equal(
    (
      await json(
        "put",
        `/admin/users/${user.user.id}/role`,
        { role: "reviewer" },
        user.accessToken,
      )
    ).status,
    403,
  );
  assert.equal(
    (
      await json(
        "post",
        `/admin/role-requests/${randomUUID()}/decision`,
        { decision: "approved" },
        user.accessToken,
      )
    ).status,
    403,
  );
  assert.equal(
    (
      await json(
        "post",
        "/access/role-request",
        { reason: "Short" },
        user.accessToken,
      )
    ).status,
    400,
  );
  assert.equal(
    (
      await json(
        "post",
        "/access/role-request",
        {
          reason: "A sufficient reason",
          userId: randomUUID(),
          role: "super_admin",
        },
        user.accessToken,
      )
    ).status,
    400,
  );
});

test("super admin creates user/reviewer accounts with OTP and records the granting actor", async () => {
  await seedAdmin();
  for (const role of ["user", "reviewer"]) {
    const email = `created-${role}@example.test`;
    const created = await json(
      "post",
      "/admin/users",
      { email: ` ${email.toUpperCase()} `, password, role },
      admin.accessToken,
    );
    assert.equal(created.status, 201);
    assert.equal(created.body.nextStep, "VERIFY_EMAIL");
    assert.equal(created.body.user.emailVerified, false);
    assert.equal(created.body.user.role, role);
    assert.equal(created.body.user.email, email);
    assert.equal(JSON.stringify(created.body).includes("password"), false);
    assert.equal(
      (await json("post", "/auth/login", { email, password })).status,
      403,
    );
    const session = await verify(email);
    assert.equal(session.user.role, role);
    const audit = await pool.query(
      "SELECT * FROM role_audit_events WHERE target_user_id=$1",
      [session.user.id],
    );
    assert.equal(audit.rowCount, 1);
    assert.equal(audit.rows[0].actor_id, admin.user.id);
    assert.equal(audit.rows[0].previous_role, null);
    assert.equal(audit.rows[0].new_role, role);
    assert.equal(
      (
        await pool.query("SELECT 1 FROM kyc_profiles WHERE user_id=$1", [
          session.user.id,
        ])
      ).rowCount,
      1,
    );
  }
  const listed = await json(
    "get",
    "/admin/users?limit=1&offset=0",
    undefined,
    admin.accessToken,
  );
  assert.equal(listed.status, 200);
  assert.equal(listed.body.users.length, 1);
  assert.ok(listed.body.total >= 4);
  assert.equal(JSON.stringify(listed.body).includes("password_hash"), false);
});

test("privileged account cannot be changed and role inputs, identifiers and pagination are strict", async () => {
  await seedAdmin();
  assert.equal(
    (
      await json(
        "put",
        `/admin/users/${admin.user.id}/role`,
        { role: "user" },
        admin.accessToken,
      )
    ).status,
    403,
  );
  assert.equal(
    (
      await json(
        "post",
        "/admin/users",
        { email: "new-root@example.test", password, role: "super_admin" },
        admin.accessToken,
      )
    ).status,
    400,
  );
  assert.equal(
    (
      await json(
        "post",
        "/admin/users",
        { email: "created-user@example.test", password, role: "user" },
        admin.accessToken,
      )
    ).status,
    409,
  );
  assert.equal(
    (
      await json(
        "post",
        "/admin/users",
        { email: "weak@example.test", password: "weak", role: "user" },
        admin.accessToken,
      )
    ).status,
    400,
  );
  assert.equal(
    (await json("get", "/admin/users?limit=-1", undefined, admin.accessToken))
      .status,
    400,
  );
  assert.equal(
    (
      await json(
        "get",
        "/admin/users?limit=51&unused=true",
        undefined,
        admin.accessToken,
      )
    ).status,
    400,
  );
  assert.equal(
    (
      await json(
        "put",
        "/admin/users/not-a-uuid/role",
        { role: "reviewer" },
        admin.accessToken,
      )
    ).status,
    400,
  );
  assert.equal(
    (
      await json(
        "put",
        `/admin/users/${randomUUID()}/role`,
        { role: "reviewer" },
        admin.accessToken,
      )
    ).status,
    404,
  );
});

test("users submit one pending request, admin approvals grant rights and decision identity is retained", async () => {
  const user = await register("request-approved@example.test");
  assert.equal(
    (await json("get", "/access/role-request", undefined, user.accessToken))
      .body.request,
    null,
  );
  const created = await json(
    "post",
    "/access/role-request",
    { reason: "I am responsible for onboarding reviews." },
    user.accessToken,
  );
  assert.equal(created.status, 201);
  assert.equal(created.body.request.status, "pending");
  assert.equal(created.body.request.userId, user.user.id);
  assert.equal(
    (
      await json(
        "post",
        "/access/role-request",
        { reason: "Duplicate request" },
        user.accessToken,
      )
    ).status,
    409,
  );
  const requests = await json(
    "get",
    "/admin/role-requests",
    undefined,
    admin.accessToken,
  );
  assert.ok(
    requests.body.requests.some(
      (item: { id: string }) => item.id === created.body.request.id,
    ),
  );
  const decision = await json(
    "post",
    `/admin/role-requests/${created.body.request.id}/decision`,
    { decision: "approved", reason: "Assigned review duties" },
    admin.accessToken,
  );
  assert.equal(decision.status, 200);
  assert.equal(decision.body.request.status, "approved");
  assert.equal(decision.body.user.role, "reviewer");
  assert.equal(
    (await json("get", "/auth/me", undefined, user.accessToken)).body.user.role,
    "reviewer",
  );
  assert.equal(
    (
      await json(
        "post",
        `/admin/role-requests/${created.body.request.id}/decision`,
        { decision: "approved" },
        admin.accessToken,
      )
    ).status,
    409,
  );
  assert.equal(
    (
      await json(
        "post",
        "/access/role-request",
        { reason: "Already reviewer" },
        user.accessToken,
      )
    ).status,
    409,
  );
  const row = (
    await pool.query(
      "SELECT decided_by,decided_at FROM role_requests WHERE id=$1",
      [created.body.request.id],
    )
  ).rows[0];
  assert.equal(row.decided_by, admin.user.id);
  assert.ok(row.decided_at);
  const audit = (
    await pool.query(
      "SELECT * FROM role_audit_events WHERE target_user_id=$1",
      [user.user.id],
    )
  ).rows[0];
  assert.equal(audit.actor_id, admin.user.id);
  assert.equal(audit.previous_role, "user");
  assert.equal(audit.new_role, "reviewer");
});

test("grant/revoke affects existing sessions and direct granting settles pending permission requests", async () => {
  const user = await register("direct-role@example.test");
  const requestCreated = await json(
    "post",
    "/access/role-request",
    { reason: "Need access for the review team" },
    user.accessToken,
  );
  const granted = await json(
    "put",
    `/admin/users/${user.user.id}/role`,
    { role: "reviewer", reason: "Joining the review team" },
    admin.accessToken,
  );
  assert.equal(granted.status, 200);
  assert.equal(granted.body.user.role, "reviewer");
  assert.equal(
    (await json("get", "/auth/me", undefined, user.accessToken)).body.user.role,
    "reviewer",
  );
  const refreshed = await json("post", "/auth/refresh", {
    refreshToken: user.refreshToken,
  });
  assert.equal(refreshed.body.user.role, "reviewer");
  const requestRow = (
    await pool.query("SELECT * FROM role_requests WHERE id=$1", [
      requestCreated.body.request.id,
    ])
  ).rows[0];
  assert.equal(requestRow.status, "approved");
  assert.equal(requestRow.decided_by, admin.user.id);
  assert.equal(
    (
      await json(
        "put",
        `/admin/users/${user.user.id}/role`,
        { role: "user" },
        refreshed.body.accessToken,
      )
    ).status,
    403,
  );
  const revoked = await json(
    "put",
    `/admin/users/${user.user.id}/role`,
    { role: "user", reason: "Review assignment ended" },
    admin.accessToken,
  );
  assert.equal(revoked.status, 200);
  assert.equal(
    (await json("get", "/auth/me", undefined, refreshed.body.accessToken)).body
      .user.role,
    "user",
  );
  assert.equal(
    (await json("get", "/reviews", undefined, refreshed.body.accessToken))
      .status,
    403,
  );
  assert.equal(
    (
      await pool.query(
        "SELECT 1 FROM role_audit_events WHERE target_user_id=$1",
        [user.user.id],
      )
    ).rowCount,
    2,
  );
  assert.equal(
    (
      await json(
        "post",
        "/access/role-request",
        { reason: "Review duties assigned again" },
        refreshed.body.accessToken,
      )
    ).status,
    201,
  );
});

test("rejection preserves the user's role and a later request can be submitted", async () => {
  const user = await register("request-rejected@example.test");
  const created = await json(
    "post",
    "/access/role-request",
    { reason: "I want reviewer access" },
    user.accessToken,
  );
  const rejected = await json(
    "post",
    `/admin/role-requests/${created.body.request.id}/decision`,
    { decision: "rejected", reason: "Complete training first" },
    admin.accessToken,
  );
  assert.equal(rejected.status, 200);
  assert.equal(rejected.body.request.status, "rejected");
  assert.equal(rejected.body.request.decisionReason, "Complete training first");
  assert.equal(
    (await json("get", "/auth/me", undefined, user.accessToken)).body.user.role,
    "user",
  );
  assert.equal(
    (
      await pool.query(
        "SELECT 1 FROM role_audit_events WHERE target_user_id=$1",
        [user.user.id],
      )
    ).rowCount,
    0,
  );
  const newer = await json(
    "post",
    "/access/role-request",
    { reason: "I have completed training" },
    user.accessToken,
  );
  assert.equal(newer.status, 201);
  assert.notEqual(newer.body.request.id, created.body.request.id);
  assert.equal(
    (await json("get", "/access/role-request", undefined, user.accessToken))
      .body.request.id,
    newer.body.request.id,
  );
});

test("concurrent request submission and approval each persist one successful transition", async () => {
  const user = await register("request-concurrent@example.test");
  const responses = await Promise.all([
    json(
      "post",
      "/access/role-request",
      { reason: "Review request" },
      user.accessToken,
    ),
    json(
      "post",
      "/access/role-request",
      { reason: "Review request again" },
      user.accessToken,
    ),
  ]);
  assert.deepEqual(
    responses.map((response) => response.status).sort(),
    [201, 409],
  );
  const id = responses.find((response) => response.status === 201)!.body.request
    .id;
  const decisions = await Promise.all([
    json(
      "post",
      `/admin/role-requests/${id}/decision`,
      { decision: "approved" },
      admin.accessToken,
    ),
    json(
      "post",
      `/admin/role-requests/${id}/decision`,
      { decision: "approved" },
      admin.accessToken,
    ),
  ]);
  assert.deepEqual(
    decisions.map((response) => response.status).sort(),
    [200, 409],
  );
  assert.equal(
    (
      await pool.query(
        "SELECT 1 FROM role_audit_events WHERE target_user_id=$1",
        [user.user.id],
      )
    ).rowCount,
    1,
  );
});

test("permission queues paginate all matching requests and callers see only their own latest request", async () => {
  const first = await register("request-paged-first@example.test");
  const second = await register("request-paged-second@example.test");
  const firstRequest = await json(
    "post",
    "/access/role-request",
    { reason: "First paginated review request" },
    first.accessToken,
  );
  const secondRequest = await json(
    "post",
    "/access/role-request",
    { reason: "Second paginated review request" },
    second.accessToken,
  );
  assert.equal(
    (await json("get", "/access/role-request", undefined, first.accessToken))
      .body.request.id,
    firstRequest.body.request.id,
  );
  assert.equal(
    (await json("get", "/access/role-request", undefined, second.accessToken))
      .body.request.id,
    secondRequest.body.request.id,
  );
  const page = await json(
    "get",
    "/admin/role-requests?limit=1&offset=0",
    undefined,
    admin.accessToken,
  );
  assert.equal(page.status, 200);
  assert.equal(page.body.requests.length, 1);
  assert.ok(page.body.total >= 2);
  const next = await json(
    "get",
    "/admin/role-requests?limit=1&offset=1",
    undefined,
    admin.accessToken,
  );
  assert.notEqual(next.body.requests[0].id, page.body.requests[0].id);
  assert.equal(next.body.total, page.body.total);
  const rejected = await json(
    "get",
    "/admin/role-requests?status=rejected",
    undefined,
    admin.accessToken,
  );
  assert.ok(rejected.body.requests.length >= 1);
  assert.ok(
    rejected.body.requests.every(
      (item: { status: string }) => item.status === "rejected",
    ),
  );
  assert.equal(
    (
      await json(
        "get",
        "/admin/role-requests?status=invalid",
        undefined,
        admin.accessToken,
      )
    ).status,
    400,
  );
});

test("admin account creation retains atomic account/profile/audit and retryable email during SMTP failure", async () => {
  const failing = await buildApp(config, pool, {
    send: async () => {
      throw new Error("Synthetic SMTP outage");
    },
  });
  try {
    const email = "created-mail-outage@example.test";
    const response = await json(
      "post",
      "/admin/users",
      { email, password, role: "reviewer" },
      admin.accessToken,
      failing,
    );
    assert.equal(response.status, 503);
    assert.equal(response.body.error.code, "EMAIL_DELIVERY_FAILED");
    const user = (
      await pool.query("SELECT * FROM users WHERE email_normalized=$1", [email])
    ).rows[0];
    assert.equal(user.role, "reviewer");
    assert.equal(user.email_verified_at, null);
    assert.equal(
      (
        await pool.query("SELECT 1 FROM kyc_profiles WHERE user_id=$1", [
          user.id,
        ])
      ).rowCount,
      1,
    );
    assert.equal(
      (
        await pool.query(
          "SELECT 1 FROM role_audit_events WHERE target_user_id=$1 AND actor_id=$2",
          [user.id, admin.user.id],
        )
      ).rowCount,
      1,
    );
    assert.equal(
      (
        await pool.query(
          "SELECT attempt_count FROM email_outbox WHERE user_id=$1",
          [user.id],
        )
      ).rows[0].attempt_count,
      1,
    );
    assert.equal(
      (
        await json(
          "post",
          "/admin/users",
          { email, password, role: "reviewer" },
          admin.accessToken,
        )
      ).status,
      409,
    );
  } finally {
    await failing.close();
  }
});
