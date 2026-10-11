import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, test } from "node:test";
import EmbeddedPostgres from "embedded-postgres";
import { Pool } from "pg";
import request from "supertest";
import { buildApp } from "../src/app.js";
import { passwordHash } from "../src/auth/password.js";
import type { Config } from "../src/config.js";
import { migrate } from "../src/database.js";

type Status =
  "not_started" | "in_progress" | "pending_review" | "verified" | "rejected";
interface Candidate {
  id: string;
  email: string;
  status: Status;
  submittedAt: string;
}
interface Actor {
  id: string;
  token: string;
}

let directory: string;
let postgres: EmbeddedPostgres;
let pool: Pool;
let app: Awaited<ReturnType<typeof buildApp>>;
let reviewer: Actor;
let administrator: Actor;
let ordinary: Actor;
let candidates: Candidate[];
const password = "ListFixture123!";
const reviewerEmail = "filter-case.reviewer@example.test";

before(async () => {
  directory = await mkdtemp(join(tmpdir(), "kyc-review-list-test-"));
  postgres = new EmbeddedPostgres({
    databaseDir: join(directory, "postgres"),
    port: 55445,
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
      "postgresql://postgres:test-only@localhost:55445/postgres",
  });
  await migrate(pool);
  const config: Config = {
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
    rateLimitMax: 200,
    maxUploadBytes: 10 * 1024 * 1024,
  };
  app = await buildApp(config, pool, { send: async () => {} });
  reviewer = await actor(reviewerEmail, "reviewer");
  administrator = await actor("list-admin@example.test", "super_admin");
  ordinary = await actor("list-ordinary@example.test", "user");
  await pool.query(
    "UPDATE kyc_profiles SET status='pending_review',submitted_at='2025-01-01T00:00:00Z' WHERE user_id=$1",
    [reviewer.id],
  );
  const fixtures: Array<[string, Status, number]> = [
    ["Alice", "pending_review", 3],
    ["bob", "pending_review", 3],
    ["carol", "verified", 1],
    ["dan", "rejected", 2],
    ["percent%name", "pending_review", 4],
    ["under_name", "verified", 5],
    ["back\\name", "rejected", 6],
    ["percentXname", "verified", 7],
    ["underXname", "pending_review", 8],
    ["draft", "in_progress", 9],
    ["new", "not_started", 10],
  ];
  candidates = [];
  for (const [name, status, day] of fixtures) {
    const candidate = {
      id: randomUUID(),
      email: `filter-case.${name}@example.test`,
      status,
      submittedAt: `2025-01-${String(day).padStart(2, "0")}T00:00:00.000Z`,
    };
    await pool.query(
      "INSERT INTO users(id,email_normalized,password_hash,email_verified_at,status) VALUES($1,$2,'unused',now(),'active')",
      [candidate.id, candidate.email],
    );
    await pool.query(
      "INSERT INTO kyc_profiles(id,user_id,status,submitted_at) VALUES($1,$2,$3,$4)",
      [randomUUID(), candidate.id, status, candidate.submittedAt],
    );
    candidates.push(candidate);
  }
});

after(async () => {
  await app?.close();
  await pool?.end();
  await postgres?.stop();
  if (directory) await rm(directory, { recursive: true, force: true });
});

async function actor(email: string, role: "user" | "reviewer" | "super_admin") {
  const id = randomUUID();
  await pool.query(
    "INSERT INTO users(id,email_normalized,password_hash,email_verified_at,status,role) VALUES($1,$2,$3,now(),'active',$4)",
    [id, email, await passwordHash(password), role],
  );
  await pool.query("INSERT INTO kyc_profiles(id,user_id) VALUES($1,$2)", [
    randomUUID(),
    id,
  ]);
  const response = await request(app.getHttpServer())
    .post("/api/v1/auth/login")
    .send({ email, password });
  assert.equal(response.status, 200);
  return { id, token: response.body.accessToken as string };
}

async function list(query: string, token: string | undefined = reviewer.token) {
  let call = request(app.getHttpServer()).get(`/api/v1/reviews${query}`);
  if (token) call = call.set("authorization", `Bearer ${token}`);
  return call;
}

function expected(status: "pending_review" | "verified" | "rejected" | "all") {
  return candidates
    .filter((candidate) =>
      status === "all"
        ? ["pending_review", "verified", "rejected"].includes(candidate.status)
        : candidate.status === status,
    )
    .sort(
      (left, right) =>
        left.submittedAt.localeCompare(right.submittedAt) ||
        left.id.localeCompare(right.id),
    )
    .map((candidate) => ({
      userId: candidate.id,
      email: candidate.email,
      status: candidate.status,
      submittedAt: candidate.submittedAt,
    }));
}

test("omitting review filters preserves the pending queue and self exclusion", async () => {
  const response = await list("");
  assert.equal(response.status, 200);
  assert.deepEqual(response.body.profiles, expected("pending_review"));
  assert.equal(response.body.total, 4);
});

test("review status filters include approved and rejected submissions, while all excludes drafts", async () => {
  for (const status of [
    "pending_review",
    "verified",
    "rejected",
    "all",
  ] as const) {
    const response = await list(`?status=${status}`);
    assert.equal(response.status, 200);
    assert.deepEqual(response.body.profiles, expected(status));
    assert.equal(response.body.total, expected(status).length);
  }
  const response = await list("?status=verified", administrator.token);
  assert.equal(response.status, 200);
  assert.deepEqual(response.body.profiles, expected("verified"));
});

test("review search matches the displayed email case-insensitively and trims surrounding whitespace", async () => {
  const response = await list(
    `?status=all&search=${encodeURIComponent("  ALICE@EXAMPLE  ")}`,
  );
  assert.equal(response.status, 200);
  const alice = expected("pending_review").find((candidate) =>
    candidate.email.includes("Alice"),
  );
  assert.deepEqual(response.body.profiles, [alice]);
  assert.equal(response.body.total, 1);
  const empty = await list("?status=all&search=%20%20%20");
  assert.equal(empty.status, 200);
  assert.deepEqual(empty.body.profiles, expected("all"));
  const absent = await list("?status=all&search=missing-applicant");
  assert.equal(absent.status, 200);
  assert.deepEqual(absent.body, { profiles: [], total: 0 });
});

test("review search treats percent, underscore and backslash as literal characters", async () => {
  for (const [search, email] of [
    ["%", "filter-case.percent%name@example.test"],
    ["_", "filter-case.under_name@example.test"],
    ["\\", "filter-case.back\\name@example.test"],
  ]) {
    const response = await list(
      `?status=all&search=${encodeURIComponent(search!)}`,
    );
    assert.equal(response.status, 200);
    assert.equal(response.body.total, 1);
    assert.deepEqual(
      response.body.profiles.map((profile: { email: string }) => profile.email),
      [email],
    );
  }
  const quoted = await list(
    `?status=all&search=${encodeURIComponent("' OR true --")}`,
  );
  assert.equal(quoted.status, 200);
  assert.deepEqual(quoted.body, { profiles: [], total: 0 });
});

test("search and status apply before pagination with an exact filtered total and stable ordering", async () => {
  const matches = expected("all");
  const pages: unknown[] = [];
  for (let offset = 0; offset < matches.length + 2; offset += 2) {
    const response = await list(
      `?status=all&search=FILTER-CASE&limit=2&offset=${offset}`,
    );
    assert.equal(response.status, 200);
    assert.equal(response.body.total, 9);
    assert.deepEqual(response.body.profiles, matches.slice(offset, offset + 2));
    pages.push(...response.body.profiles);
  }
  assert.deepEqual(pages, matches);
  const selected = await list("?status=verified&search=carol&limit=1&offset=1");
  assert.equal(selected.status, 200);
  assert.deepEqual(selected.body, { profiles: [], total: 1 });
  const self = await list(`?status=all&search=${reviewerEmail}`);
  assert.equal(self.status, 200);
  assert.deepEqual(self.body, { profiles: [], total: 0 });
});

test("review filters validate statuses, search size, scalar values and strict pagination", async () => {
  for (const query of [
    "status=approved",
    "status=in_progress",
    "status=",
    "status=verified&status=rejected",
    "search=alice&search=bob",
    `search=${"x".repeat(255)}`,
    "limit=0",
    "limit=101",
    "offset=-1",
    "offset=1000001",
    "extra=1",
  ]) {
    assert.equal((await list(`?${query}`)).status, 400, query);
  }
  assert.equal(
    (await list(`?status=all&search=${"x".repeat(254)}`)).status,
    200,
  );
});

test("completed review list entries retain pending-only detail, media and decision restrictions", async () => {
  for (const candidate of candidates.filter((value) =>
    ["verified", "rejected"].includes(value.status),
  )) {
    for (const suffix of ["", `/media/document?submissionId=${randomUUID()}`]) {
      const response = await request(app.getHttpServer())
        .get(`/api/v1/reviews/${candidate.id}${suffix}`)
        .set("authorization", `Bearer ${reviewer.token}`);
      assert.equal(response.status, 404);
      assert.equal(response.body.error.code, "KYC_REVIEW_NOT_FOUND");
    }
    const decision = await request(app.getHttpServer())
      .post(`/api/v1/reviews/${candidate.id}/decision`)
      .set("authorization", `Bearer ${reviewer.token}`)
      .send({ submissionId: randomUUID(), decision: "verified" });
    assert.equal(decision.status, 409);
  }
  const count = await pool.query("SELECT count(*) AS total FROM kyc_reviews");
  assert.equal(count.rows[0].total, "0");
});

test("filtered lists retain authentication, live reviewer roles and own-profile exclusion for every status", async () => {
  assert.equal(
    (
      await request(app.getHttpServer()).get(
        "/api/v1/reviews?status=all&search=filter-case",
      )
    ).status,
    401,
  );
  assert.equal(
    (await list("?status=all&search=filter-case", ordinary.token)).status,
    403,
  );
  for (const status of ["pending_review", "verified", "rejected"] as const) {
    await pool.query("UPDATE kyc_profiles SET status=$2 WHERE user_id=$1", [
      reviewer.id,
      status,
    ]);
    const response = await list(`?status=${status}&search=${reviewerEmail}`);
    assert.equal(response.status, 200);
    assert.deepEqual(response.body, { profiles: [], total: 0 });
    const all = await list(`?status=all&search=${reviewerEmail}`);
    assert.equal(all.status, 200);
    assert.deepEqual(all.body, { profiles: [], total: 0 });
  }
  await pool.query("UPDATE users SET role='user' WHERE id=$1", [reviewer.id]);
  const denied = await list("?status=all&search=filter-case");
  assert.equal(denied.status, 403);
  assert.equal(denied.body.profiles, undefined);
});
