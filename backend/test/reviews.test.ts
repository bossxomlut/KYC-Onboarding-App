import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, test } from "node:test";
import EmbeddedPostgres from "embedded-postgres";
import { Pool } from "pg";
import sharp from "sharp";
import request from "supertest";
import { buildApp } from "../src/app.js";
import { passwordHash } from "../src/auth/password.js";
import type { Config } from "../src/config.js";
import { migrate } from "../src/database.js";
import { reviewProfile } from "../src/kyc/kyc.repository.js";
import { encrypt } from "../src/security.js";

let directory: string;
let postgres: EmbeddedPostgres;
let pool: Pool;
let app: Awaited<ReturnType<typeof buildApp>>;
let config: Config;
let image: Buffer;
let applicant: Actor;
let reviewer: Actor;
let otherReviewer: Actor;
let administrator: Actor;
const password = "ReviewerFixture123!";
const details = {
  fullName: "Synthetic Review Applicant",
  dateOfBirth: "1990-01-01",
  nationality: "VN",
  address: "123 Synthetic Street, Demo City",
  documentNumber: "SYNTHETIC-1234",
};

interface Actor {
  id: string;
  email: string;
  token: string;
}

before(async () => {
  directory = await mkdtemp(join(tmpdir(), "kyc-reviews-test-"));
  postgres = new EmbeddedPostgres({
    databaseDir: join(directory, "postgres"),
    port: 55441,
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
      "postgresql://postgres:test-only@localhost:55441/postgres",
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
    resetLink: "kycapp://app/reset-password",
    rateLimitMax: 200,
    maxUploadBytes: 10 * 1024 * 1024,
  };
  app = await buildApp(config, pool, { send: async () => {} });
  image = await sharp({
    create: { width: 32, height: 24, channels: 3, background: "#125773" },
  })
    .jpeg()
    .toBuffer();
  applicant = await actor("applicant", "user");
  reviewer = await actor("reviewer", "reviewer");
  otherReviewer = await actor("other-reviewer", "reviewer");
  administrator = await actor("administrator", "super_admin");
});

after(async () => {
  await app?.close();
  await pool?.end();
  await postgres?.stop();
  if (directory) await rm(directory, { recursive: true, force: true });
});

async function json(
  method: "GET" | "POST",
  path: string,
  token?: string,
  body?: unknown,
) {
  const server = request(app.getHttpServer());
  let call = server[method === "GET" ? "get" : "post"](`/api/v1${path}`);
  if (token) call = call.set("authorization", `Bearer ${token}`);
  if (body !== undefined) call = call.send(body as object);
  return call;
}

async function actor(name: string, role: "user" | "reviewer" | "super_admin") {
  const id = randomUUID();
  const email = `${name}-${id}@example.test`;
  await pool.query(
    "INSERT INTO users(id,email_normalized,password_hash,email_verified_at,status,role) VALUES($1,$2,$3,now(),'active',$4)",
    [id, email, await passwordHash(password), role],
  );
  await pool.query("INSERT INTO kyc_profiles(id,user_id) VALUES($1,$2)", [
    randomUUID(),
    id,
  ]);
  const login = await json("POST", "/auth/login", undefined, {
    email,
    password,
  });
  assert.equal(login.status, 200);
  return { id, email, token: login.body.accessToken as string };
}

async function pending(userId: string) {
  await pool.query(
    "UPDATE kyc_profiles SET status='pending_review',submitted_at=now(),personal_details=$2 WHERE user_id=$1",
    [
      userId,
      encrypt(Buffer.from(JSON.stringify(details)), config.mediaKey).toString(
        "base64",
      ),
    ],
  );
  await mkdir(config.mediaDir, { recursive: true, mode: 0o700 });
  for (const kind of ["document", "selfie"]) {
    const key = randomUUID();
    await writeFile(
      join(config.mediaDir, key),
      encrypt(image, config.mediaKey),
      {
        mode: 0o600,
      },
    );
    await pool.query(
      "INSERT INTO kyc_media(id,user_id,kind,document_type,mime_type,size,storage_key) VALUES($1,$2,$3,$4,'image/jpeg',$5,$6) ON CONFLICT(user_id,kind) DO UPDATE SET storage_key=EXCLUDED.storage_key",
      [
        randomUUID(),
        userId,
        kind,
        kind === "document" ? "passport" : null,
        image.length,
        key,
      ],
    );
  }
}

test("review routes require an authenticated reviewer and never expose other users to ordinary accounts", async () => {
  await pending(applicant.id);
  const routes: Array<["GET" | "POST", string, object?]> = [
    ["GET", "/reviews"],
    ["GET", `/reviews/${applicant.id}`],
    ["GET", `/reviews/${applicant.id}/media/document`],
    ["POST", `/reviews/${applicant.id}/decision`, { decision: "verified" }],
  ];
  for (const [method, path, body] of routes) {
    assert.equal((await json(method, path, undefined, body)).status, 401);
    const denied = await json(method, path, applicant.token, body);
    assert.equal(denied.status, 403);
    assert.equal(JSON.stringify(denied.body).includes(details.fullName), false);
  }
  await assert.rejects(
    reviewProfile(pool, applicant.id, "verified"),
    (error: any) => error.statusCode === 403 || error.status === 403,
  );
  assert.equal(
    (
      await pool.query("SELECT status FROM kyc_profiles WHERE user_id=$1", [
        applicant.id,
      ])
    ).rows[0].status,
    "pending_review",
  );
});

test("review queue paginates deterministically and excludes the current reviewer's own profile", async () => {
  await pending(reviewer.id);
  const queue = await json("GET", "/reviews?limit=1&offset=0", reviewer.token);
  assert.equal(queue.status, 200);
  assert.equal(queue.body.total, 1);
  assert.equal(queue.body.profiles.length, 1);
  assert.deepEqual(queue.body.profiles[0], {
    userId: applicant.id,
    email: applicant.email,
    status: "pending_review",
    submittedAt: queue.body.profiles[0].submittedAt,
  });
  assert.ok(queue.body.profiles[0].submittedAt);
  assert.equal(
    JSON.stringify(queue.body).includes(details.documentNumber),
    false,
  );
  assert.equal(
    (await json("GET", "/reviews?limit=1&offset=1", reviewer.token)).body
      .profiles.length,
    0,
  );
  for (const query of [
    "limit=0",
    "limit=101",
    "offset=-1",
    "limit=abc",
    "extra=1",
  ]) {
    assert.equal(
      (await json("GET", `/reviews?${query}`, reviewer.token)).status,
      400,
    );
  }
});

test("reviewers can inspect pending details and authenticated JPEGs, with self and non-pending access denied", async () => {
  const profile = await json("GET", `/reviews/${applicant.id}`, reviewer.token);
  assert.equal(profile.status, 200);
  assert.deepEqual(profile.body.user, {
    id: applicant.id,
    email: applicant.email,
  });
  assert.deepEqual(profile.body.profile.personalDetails, details);
  for (const kind of ["document", "selfie"]) {
    const media = await json(
      "GET",
      `/reviews/${applicant.id}/media/${kind}`,
      reviewer.token,
    );
    assert.equal(media.status, 200);
    assert.equal(media.headers["content-type"], "image/jpeg");
    assert.equal(media.headers["cache-control"], "no-store");
    assert.deepEqual(media.body, image);
  }
  for (const suffix of ["", "/media/document"]) {
    assert.equal(
      (await json("GET", `/reviews/${reviewer.id}${suffix}`, reviewer.token))
        .status,
      403,
    );
    assert.equal(
      (
        await json(
          "GET",
          `/reviews/${administrator.id}${suffix}`,
          reviewer.token,
        )
      ).status,
      404,
    );
  }
  assert.equal(
    (
      await json("POST", `/reviews/${reviewer.id}/decision`, reviewer.token, {
        decision: "verified",
      })
    ).status,
    403,
  );
  assert.equal(
    (await json("GET", "/reviews/not-a-uuid", reviewer.token)).status,
    400,
  );
  assert.equal(
    (await json("GET", `/reviews/${randomUUID()}`, reviewer.token)).status,
    404,
  );
  assert.equal(
    (
      await json(
        "GET",
        `/reviews/${applicant.id}/media/unknown`,
        reviewer.token,
      )
    ).status,
    400,
  );
});

test("super admin can reject a pending profile, recording the authenticated decision maker", async () => {
  for (const body of [
    { decision: "rejected" },
    { decision: "rejected", reason: "Retake", requiredSteps: [] },
    { decision: "rejected", reason: "Retake", requiredSteps: ["invalid"] },
    { decision: "verified", reviewedBy: reviewer.id },
  ]) {
    assert.equal(
      (
        await json(
          "POST",
          `/reviews/${applicant.id}/decision`,
          administrator.token,
          body,
        )
      ).status,
      400,
    );
  }
  const rejected = await json(
    "POST",
    `/reviews/${applicant.id}/decision`,
    administrator.token,
    {
      decision: "rejected",
      reason: "  Synthetic image needs retaking  ",
      requiredSteps: ["selfie"],
    },
  );
  assert.equal(rejected.status, 200);
  assert.equal(rejected.body.profile.status, "rejected");
  assert.equal(
    rejected.body.profile.rejectionReason,
    "Synthetic image needs retaking",
  );
  assert.deepEqual(rejected.body.profile.requiredSteps, ["selfie"]);
  const audit = await pool.query(
    "SELECT user_id,reviewed_by,decision,required_steps,reason FROM kyc_reviews WHERE user_id=$1",
    [applicant.id],
  );
  assert.equal(audit.rowCount, 1);
  assert.equal(audit.rows[0].reviewed_by, administrator.id);
  assert.equal(audit.rows[0].decision, "rejected");
  assert.equal(audit.rows[0].reason, "Synthetic image needs retaking");
  assert.deepEqual(audit.rows[0].required_steps, ["selfie"]);
  assert.equal(
    (
      await json("POST", `/reviews/${applicant.id}/decision`, reviewer.token, {
        decision: "verified",
      })
    ).status,
    409,
  );
  assert.equal(
    (await json("GET", `/reviews/${applicant.id}`, reviewer.token)).status,
    404,
  );
});

test("concurrent reviewer decisions produce a single audit record and leave the profile locked", async () => {
  const candidate = await actor("concurrent-applicant", "user");
  await pending(candidate.id);
  const results = await Promise.all([
    json("POST", `/reviews/${candidate.id}/decision`, reviewer.token, {
      decision: "verified",
    }),
    json("POST", `/reviews/${candidate.id}/decision`, otherReviewer.token, {
      decision: "verified",
    }),
  ]);
  assert.deepEqual(results.map((item) => item.status).sort(), [200, 409]);
  const audit = await pool.query(
    "SELECT reviewed_by FROM kyc_reviews WHERE user_id=$1",
    [candidate.id],
  );
  assert.equal(audit.rowCount, 1);
  assert.ok(
    [reviewer.id, otherReviewer.id].includes(audit.rows[0].reviewed_by),
  );
  assert.equal(
    (
      await json(
        "GET",
        `/reviews/${candidate.id}/media/document`,
        reviewer.token,
      )
    ).status,
    404,
  );
});

test("revoked reviewer privileges take effect on the original access token for all review routes", async () => {
  const revoked = await actor("revoked-reviewer", "reviewer");
  const candidate = await actor("revocation-applicant", "user");
  await pending(candidate.id);
  assert.equal((await json("GET", "/reviews", revoked.token)).status, 200);
  await pool.query("UPDATE users SET role='user' WHERE id=$1", [revoked.id]);
  for (const [method, path, body] of [
    ["GET", "/reviews", undefined],
    ["GET", `/reviews/${candidate.id}`, undefined],
    ["GET", `/reviews/${candidate.id}/media/document`, undefined],
    ["POST", `/reviews/${candidate.id}/decision`, { decision: "verified" }],
  ] as const) {
    assert.equal((await json(method, path, revoked.token, body)).status, 403);
  }
  await assert.rejects(
    reviewProfile(pool, candidate.id, "verified", undefined, [], revoked.id),
    (error: any) => error.statusCode === 403 || error.status === 403,
  );
  assert.equal(
    (await json("GET", "/auth/me", revoked.token)).body.user.role,
    "user",
  );
});
