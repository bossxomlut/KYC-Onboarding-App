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
import { encrypt } from "../src/security.js";

let directory: string;
let postgres: EmbeddedPostgres;
let pool: Pool;
let app: Awaited<ReturnType<typeof buildApp>>;
let config: Config;
let originalImage: Buffer;
let replacementImage: Buffer;
let sharedAdministrator: Actor | undefined;
const password = "HistoryFixture123!";
const details = {
  fullName: "Synthetic Historical Applicant",
  dateOfBirth: "1990-01-01",
  nationality: "VN",
  address: "123 Synthetic History Street, Demo City",
  documentNumber: "SYNTHETIC-HISTORY-1234",
};
const changedDetails = {
  ...details,
  fullName: "Synthetic Updated Applicant",
  address: "456 Synthetic Replacement Street, Demo City",
  documentNumber: "SYNTHETIC-HISTORY-5678",
};

interface Actor {
  id: string;
  email: string;
  token: string;
  role: "user" | "reviewer" | "super_admin";
}

interface Submission {
  id: string;
  version: number;
  profile: {
    id: string;
    status: "pending_review" | "verified" | "rejected";
    nextStep: "result";
    personalDetails: typeof details | null;
    document: { id: string; mimeType: string; size: number } | null;
    selfie: { id: string; mimeType: string; size: number } | null;
    rejectionReason: string | null;
    requiredSteps: string[];
    submittedAt: string;
    updatedAt: string;
  };
  review: {
    decision: "verified" | "rejected";
    reason: string | null;
    requiredSteps: string[];
    reviewedAt: string;
    reviewer: { id: string; email: string | null; role: string | null } | null;
  } | null;
}

before(async () => {
  directory = await mkdtemp(join(tmpdir(), "kyc-history-test-"));
  postgres = new EmbeddedPostgres({
    databaseDir: join(directory, "postgres"),
    port: 55442,
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
      "postgresql://postgres:test-only@localhost:55442/postgres",
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
  app = await buildApp(config, pool, { send: async () => {} });
  originalImage = await sharp({
    create: { width: 48, height: 32, channels: 3, background: "#125773" },
  })
    .jpeg()
    .toBuffer();
  replacementImage = await sharp({
    create: { width: 64, height: 48, channels: 3, background: "#eb7342" },
  })
    .jpeg()
    .toBuffer();
});

after(async () => {
  await app?.close();
  await pool?.end();
  await postgres?.stop();
  if (directory) await rm(directory, { recursive: true, force: true });
});

async function json(
  method: "GET" | "POST" | "PUT",
  path: string,
  token?: string,
  body?: unknown,
) {
  const server = request(app.getHttpServer());
  let call = server[method.toLowerCase() as "get" | "post" | "put"](
    `/api/v1${path}`,
  );
  if (token) call = call.set("authorization", `Bearer ${token}`);
  if (body !== undefined) call = call.send(body as object);
  return call;
}

async function actor(
  name: string,
  role: Actor["role"] = "user",
): Promise<Actor> {
  if (role === "super_admin" && sharedAdministrator) return sharedAdministrator;
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
  const authenticated = {
    id,
    email,
    role,
    token: login.body.accessToken as string,
  };
  if (role === "super_admin") sharedAdministrator = authenticated;
  return authenticated;
}

async function upload(
  applicant: Actor,
  kind: "document" | "selfie",
  bytes = originalImage,
) {
  let call = request(app.getHttpServer())
    .post(`/api/v1/kyc/media/${kind}`)
    .set("authorization", `Bearer ${applicant.token}`)
    .field("captureId", `history-capture-${randomUUID()}`);
  if (kind === "document") call = call.field("documentType", "passport");
  const response = await call.attach("file", bytes, {
    filename: "synthetic.jpg",
    contentType: "image/jpeg",
  });
  assert.equal(response.status, 200);
  return response;
}

async function completeDraft(applicant: Actor) {
  assert.equal(
    (await json("PUT", "/kyc/personal-details", applicant.token, details))
      .status,
    200,
  );
  await upload(applicant, "document");
  await upload(applicant, "selfie");
}

async function submit(applicant: Actor) {
  const response = await json("POST", "/kyc/submit", applicant.token);
  assert.equal(response.status, 200);
  assert.equal(response.body.profile.status, "pending_review");
  return response;
}

async function history(applicant: Actor, reviewer?: Actor, query = "") {
  const response = await json(
    "GET",
    reviewer
      ? `/reviews/${applicant.id}/history${query}`
      : `/kyc/history${query}`,
    (reviewer ?? applicant).token,
  );
  assert.equal(response.status, 200);
  assert.equal(typeof response.body.total, "number");
  assert.ok(Array.isArray(response.body.submissions));
  return response.body as { submissions: Submission[]; total: number };
}

function assertSubmission(submission: Submission, version: number) {
  assert.match(
    submission.id,
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
  );
  assert.equal(submission.version, version);
  assert.equal(submission.profile.nextStep, "result");
  assert.equal(
    new Date(submission.profile.submittedAt).toISOString(),
    submission.profile.submittedAt,
  );
  assert.equal(
    new Date(submission.profile.updatedAt).toISOString(),
    submission.profile.updatedAt,
  );
  assert.equal(JSON.stringify(submission).includes("storage_key"), false);
  assert.equal(JSON.stringify(submission).includes("storageKey"), false);
  if (submission.review) {
    assert.equal(
      new Date(submission.review.reviewedAt).toISOString(),
      submission.review.reviewedAt,
    );
  }
}

async function assertArchivedPhoto(
  applicant: Actor,
  submissionId: string,
  kind: "document" | "selfie",
  expected: Buffer,
  reviewer?: Actor,
) {
  const response = await json(
    "GET",
    reviewer
      ? `/reviews/${applicant.id}/history/${submissionId}/media/${kind}`
      : `/kyc/history/${submissionId}/media/${kind}`,
    (reviewer ?? applicant).token,
  );
  assert.equal(response.status, 200);
  assert.equal(response.headers["content-type"], "image/jpeg");
  assert.equal(response.headers["cache-control"], "no-store");
  assert.deepEqual(response.body, expected);
}

test("history records only real submissions and pending submit retries share one version", async () => {
  const applicant = await actor("idempotent-history");
  assert.deepEqual(await history(applicant), { submissions: [], total: 0 });
  const incomplete = await json("POST", "/kyc/submit", applicant.token);
  assert.equal(incomplete.status, 400);
  assert.equal(incomplete.body.error.code, "KYC_INCOMPLETE");
  await completeDraft(applicant);
  assert.deepEqual(await history(applicant), { submissions: [], total: 0 });

  const responses = await Promise.all([
    json("POST", "/kyc/submit", applicant.token),
    json("POST", "/kyc/submit", applicant.token),
  ]);
  assert.deepEqual(
    responses.map((response) => response.status),
    [200, 200],
  );
  assert.deepEqual(responses[0]!.body.profile, responses[1]!.body.profile);
  const recorded = await history(applicant);
  assert.equal(recorded.total, 1);
  assert.equal(recorded.submissions.length, 1);
  const first = recorded.submissions[0]!;
  assertSubmission(first, 1);
  assert.deepEqual(first.profile, responses[0]!.body.profile);
  assert.equal(first.review, null);

  const stored = await pool.query(
    "SELECT row_to_json(s)::text AS snapshot FROM kyc_submissions s WHERE user_id=$1",
    [applicant.id],
  );
  assert.equal(stored.rowCount, 1);
  for (const value of [
    details.fullName,
    details.address,
    details.documentNumber,
  ]) {
    assert.equal(stored.rows[0].snapshot.includes(value), false);
  }

  await submit(applicant);
  assert.deepEqual(await history(applicant), recorded);
});

test("rejected and verified versions retain original details, photos and reviewer identity after resubmission", async () => {
  const applicant = await actor("immutable-history");
  const reviewer = await actor("historical-reviewer", "reviewer");
  const administrator = await actor("historical-admin", "super_admin");
  await completeDraft(applicant);
  const originalDocument = await json(
    "GET",
    "/kyc/media/document",
    applicant.token,
  );
  const originalSelfie = await json(
    "GET",
    "/kyc/media/selfie",
    applicant.token,
  );
  await submit(applicant);
  const firstPending = (await history(applicant)).submissions[0]!;
  const rejected = await json(
    "POST",
    `/reviews/${applicant.id}/decision`,
    reviewer.token,
    {
      submissionId: firstPending.id,
      decision: "rejected",
      reason: "  Update synthetic details and retake photos  ",
      requiredSteps: ["selfie"],
    },
  );
  assert.equal(rejected.status, 200);
  const firstRejected = (await history(applicant, reviewer)).submissions[0]!;
  assertSubmission(firstRejected, 1);
  assert.equal(firstRejected.id, firstPending.id);
  assert.deepEqual(firstRejected.profile, rejected.body.profile);
  assert.deepEqual(firstRejected.profile.personalDetails, details);
  assert.ok(firstRejected.review);
  assert.deepEqual(firstRejected.review, {
    decision: "rejected",
    reason: "Update synthetic details and retake photos",
    requiredSteps: ["selfie"],
    reviewedAt: firstRejected.review.reviewedAt,
    reviewer: { id: reviewer.id, email: reviewer.email, role: "reviewer" },
  });

  await pool.query(
    "UPDATE users SET email_normalized=$2,role='user' WHERE id=$1",
    [reviewer.id, `changed-${reviewer.id}@example.test`],
  );
  assert.equal(
    (await json("POST", "/kyc/resubmit", applicant.token)).status,
    200,
  );
  const reopened = await json("GET", "/kyc", applicant.token);
  assert.deepEqual(reopened.body.profile.personalDetails, details);
  assert.deepEqual(
    reopened.body.profile.document,
    firstRejected.profile.document,
  );
  assert.equal(reopened.body.profile.selfie, null);
  for (const kind of ["document", "selfie"] as const) {
    await assertArchivedPhoto(
      applicant,
      firstRejected.id,
      kind,
      kind === "document" ? originalDocument.body : originalSelfie.body,
      administrator,
    );
  }
  assert.equal(
    (
      await json(
        "PUT",
        "/kyc/personal-details",
        applicant.token,
        changedDetails,
      )
    ).status,
    200,
  );
  await upload(applicant, "document", replacementImage);
  await upload(applicant, "selfie", replacementImage);
  const newDocument = await json("GET", "/kyc/media/document", applicant.token);
  const newSelfie = await json("GET", "/kyc/media/selfie", applicant.token);
  assert.notDeepEqual(newDocument.body, originalDocument.body);
  assert.notDeepEqual(newSelfie.body, originalSelfie.body);
  assert.deepEqual((await history(applicant)).submissions, [firstRejected]);

  const submitted = await submit(applicant);
  const twoVersions = await history(applicant, administrator);
  assert.equal(twoVersions.total, 2);
  assert.equal(twoVersions.submissions.length, 2);
  const second = twoVersions.submissions[0]!;
  assertSubmission(second, 2);
  assert.notEqual(second.id, firstRejected.id);
  assert.deepEqual(second.profile, submitted.body.profile);
  assert.deepEqual(second.profile.personalDetails, changedDetails);
  assert.equal(second.review, null);
  assert.deepEqual(twoVersions.submissions[1], firstRejected);
  for (const kind of ["document", "selfie"] as const) {
    await assertArchivedPhoto(
      applicant,
      firstRejected.id,
      kind,
      kind === "document" ? originalDocument.body : originalSelfie.body,
    );
    await assertArchivedPhoto(
      applicant,
      second.id,
      kind,
      kind === "document" ? newDocument.body : newSelfie.body,
      administrator,
    );
  }
  const verified = await json(
    "POST",
    `/reviews/${applicant.id}/decision`,
    administrator.token,
    { submissionId: second.id, decision: "verified" },
  );
  assert.equal(verified.status, 200);
  const completed = await history(applicant);
  assert.equal(completed.total, 2);
  assert.deepEqual(completed.submissions[1], firstRejected);
  const finalVersion = completed.submissions[0]!;
  assert.deepEqual(finalVersion.profile, verified.body.profile);
  assert.ok(finalVersion.review);
  assert.deepEqual(finalVersion.review, {
    decision: "verified",
    reason: null,
    requiredSteps: [],
    reviewedAt: finalVersion.review.reviewedAt,
    reviewer: {
      id: administrator.id,
      email: administrator.email,
      role: "super_admin",
    },
  });
  await pool.query("UPDATE users SET email_normalized=$2 WHERE id=$1", [
    administrator.id,
    `changed-${administrator.id}@example.test`,
  ]);
  assert.deepEqual(await history(applicant), completed);
  assert.deepEqual(await history(applicant, administrator), completed);
});

test("history paginates newest versions first and does not record draft corrections", async () => {
  const applicant = await actor("paginated-history");
  const reviewer = await actor("pagination-reviewer", "reviewer");
  await completeDraft(applicant);
  for (let version = 1; version <= 3; version++) {
    await submit(applicant);
    if (version === 3) break;
    const submissionId = (await history(applicant)).submissions[0]!.id;
    const rejected = await json(
      "POST",
      `/reviews/${applicant.id}/decision`,
      reviewer.token,
      {
        submissionId,
        decision: "rejected",
        reason: "Retake selfie",
        requiredSteps: ["selfie"],
      },
    );
    assert.equal(rejected.status, 200);
    assert.equal(
      (await json("POST", "/kyc/resubmit", applicant.token)).status,
      200,
    );
    await upload(applicant, "selfie", replacementImage);
    assert.equal((await history(applicant)).total, version);
  }
  const all = await history(applicant);
  assert.equal(all.total, 3);
  assert.deepEqual(
    all.submissions.map((item) => item.version),
    [3, 2, 1],
  );
  assert.equal(new Set(all.submissions.map((item) => item.id)).size, 3);
  for (let offset = 0; offset < 3; offset++) {
    const page = await history(
      applicant,
      undefined,
      `?limit=1&offset=${offset}`,
    );
    assert.equal(page.total, 3);
    assert.deepEqual(page.submissions, [all.submissions[offset]]);
    assert.deepEqual(
      await history(applicant, reviewer, `?limit=1&offset=${offset}`),
      page,
    );
  }
  assert.deepEqual(await history(applicant, undefined, "?limit=1&offset=3"), {
    submissions: [],
    total: 3,
  });
  for (const query of [
    "limit=0",
    "limit=101",
    "offset=-1",
    "limit=abc",
    "offset=1.5",
    "extra=1",
  ]) {
    for (const path of ["/kyc/history", `/reviews/${applicant.id}/history`]) {
      const token = path.startsWith("/reviews")
        ? reviewer.token
        : applicant.token;
      assert.equal((await json("GET", `${path}?${query}`, token)).status, 400);
    }
  }
});

test("concurrent reviewer decisions attach only the winning decision to the submitted version", async () => {
  const applicant = await actor("concurrent-history");
  const verifier = await actor("history-verifier", "reviewer");
  const rejector = await actor("history-rejector", "reviewer");
  await completeDraft(applicant);
  await submit(applicant);
  const pending = (await history(applicant)).submissions[0]!;
  const decisions = [
    { actor: verifier, body: { decision: "verified" } },
    {
      actor: rejector,
      body: {
        decision: "rejected",
        reason: "Synthetic selfie correction",
        requiredSteps: ["selfie"],
      },
    },
  ];
  const responses = await Promise.all(
    decisions.map((decision) =>
      json("POST", `/reviews/${applicant.id}/decision`, decision.actor.token, {
        submissionId: pending.id,
        ...decision.body,
      }),
    ),
  );
  assert.deepEqual(
    responses.map((response) => response.status).sort(),
    [200, 409],
  );
  const winnerIndex = responses.findIndex(
    (response) => response.status === 200,
  );
  const winner = decisions[winnerIndex]!;
  const archived = await history(applicant, verifier);
  assert.equal(archived.total, 1);
  assert.equal(archived.submissions.length, 1);
  const finalVersion = archived.submissions[0]!;
  assertSubmission(finalVersion, 1);
  assert.equal(finalVersion.id, pending.id);
  assert.deepEqual(finalVersion.profile, responses[winnerIndex]!.body.profile);
  assert.equal(finalVersion.review!.decision, winner.body.decision);
  assert.deepEqual(finalVersion.review!.reviewer, {
    id: winner.actor.id,
    email: winner.actor.email,
    role: "reviewer",
  });
});

test("history and archived photos enforce applicant ownership, reviewer role and self-review isolation", async () => {
  const applicant = await actor("isolated-history");
  const outsider = await actor("outsider-history");
  const reviewer = await actor("isolated-reviewer", "reviewer");
  const administrator = await actor("isolated-admin", "super_admin");
  await completeDraft(applicant);
  await submit(applicant);
  const submission = (await history(applicant)).submissions[0]!;
  const ownerMedia = `/kyc/history/${submission.id}/media/document`;
  const reviewerHistory = `/reviews/${applicant.id}/history`;
  const reviewerMedia = `${reviewerHistory}/${submission.id}/media/document`;
  for (const path of [
    "/kyc/history",
    ownerMedia,
    reviewerHistory,
    reviewerMedia,
  ]) {
    assert.equal((await json("GET", path)).status, 401);
  }
  assert.deepEqual(await history(outsider), { submissions: [], total: 0 });
  const deniedPhoto = await json("GET", ownerMedia, outsider.token);
  assert.equal(deniedPhoto.status, 404);
  assert.equal(deniedPhoto.headers["cache-control"], "no-store");
  for (const path of [reviewerHistory, reviewerMedia]) {
    const denied = await json("GET", path, outsider.token);
    assert.equal(denied.status, 403);
    assert.equal(JSON.stringify(denied.body).includes(details.fullName), false);
    assert.equal(
      JSON.stringify(denied.body).includes(details.documentNumber),
      false,
    );
    assert.equal((await json("GET", path, administrator.token)).status, 200);
  }
  for (const path of [
    `/reviews/${reviewer.id}/history`,
    `/reviews/${reviewer.id}/history/${submission.id}/media/document`,
  ]) {
    assert.equal((await json("GET", path, reviewer.token)).status, 403);
  }
  assert.equal(
    (
      await json(
        "GET",
        `/reviews/${outsider.id}/history/${submission.id}/media/document`,
        reviewer.token,
      )
    ).status,
    404,
  );
  assert.equal(
    (await json("GET", `/reviews/${randomUUID()}/history`, reviewer.token))
      .status,
    404,
  );
  for (const path of [
    "/kyc/history/not-a-uuid/media/document",
    `/kyc/history/${submission.id}/media/unknown`,
  ]) {
    assert.equal((await json("GET", path, applicant.token)).status, 400);
  }
  for (const path of [
    "/reviews/not-a-uuid/history",
    `${reviewerHistory}/not-a-uuid/media/document`,
    `${reviewerHistory}/${submission.id}/media/unknown`,
  ]) {
    assert.equal((await json("GET", path, reviewer.token)).status, 400);
  }
  assert.equal(
    (
      await json(
        "GET",
        `/kyc/history/${randomUUID()}/media/document`,
        applicant.token,
      )
    ).status,
    404,
  );
});

test("revoked reviewer role immediately removes historical list and photo access on the existing token", async () => {
  const applicant = await actor("revocation-history");
  const reviewer = await actor("revoked-history-reviewer", "reviewer");
  await completeDraft(applicant);
  await submit(applicant);
  const submissionId = (await history(applicant)).submissions[0]!.id;
  const decision = await json(
    "POST",
    `/reviews/${applicant.id}/decision`,
    reviewer.token,
    { submissionId, decision: "verified" },
  );
  assert.equal(decision.status, 200);
  const submission = (await history(applicant, reviewer)).submissions[0]!;
  const paths = [
    `/reviews/${applicant.id}/history`,
    `/reviews/${applicant.id}/history/${submission.id}/media/document`,
    `/reviews/${applicant.id}/history/${submission.id}/media/selfie`,
  ];
  for (const path of paths) {
    assert.equal((await json("GET", path, reviewer.token)).status, 200);
  }
  await pool.query("UPDATE users SET role='user' WHERE id=$1", [reviewer.id]);
  for (const path of paths) {
    assert.equal((await json("GET", path, reviewer.token)).status, 403);
  }
  const retained = (await history(applicant)).submissions[0]!;
  assert.equal(retained.review!.reviewer!.role, "reviewer");
  assert.equal(retained.review!.reviewer!.email, reviewer.email);
});

async function legacyProfile(
  applicant: Actor,
  status: "pending_review" | "rejected",
) {
  await pool.query(
    "UPDATE kyc_profiles SET status=$2,submitted_at='2026-01-02T03:04:05Z',personal_details=$3,rejection_reason=$4,required_steps=$5 WHERE user_id=$1",
    [
      applicant.id,
      status,
      encrypt(Buffer.from(JSON.stringify(details)), config.mediaKey).toString(
        "base64",
      ),
      status === "rejected" ? "Legacy synthetic correction" : null,
      status === "rejected" ? ["selfie"] : [],
    ],
  );
  await mkdir(config.mediaDir, { recursive: true, mode: 0o700 });
  for (const kind of ["document", "selfie"]) {
    const key = randomUUID();
    await writeFile(
      join(config.mediaDir, key),
      encrypt(originalImage, config.mediaKey),
      {
        mode: 0o600,
      },
    );
    await pool.query(
      "INSERT INTO kyc_media(id,user_id,kind,document_type,mime_type,size,storage_key) VALUES($1,$2,$3,$4,'image/jpeg',$5,$6)",
      [
        randomUUID(),
        applicant.id,
        kind,
        kind === "document" ? "passport" : null,
        originalImage.length,
        key,
      ],
    );
  }
}

test("legacy pending profiles acquire a historical snapshot before reviewer decisions and resubmission remove live assets", async () => {
  const applicant = await actor("legacy-pending-history");
  const reviewer = await actor("legacy-history-reviewer", "reviewer");
  await legacyProfile(applicant, "pending_review");
  const pending = await json("GET", "/kyc", applicant.token);
  const inspected = await json(
    "GET",
    `/reviews/${applicant.id}`,
    reviewer.token,
  );
  const rejected = await json(
    "POST",
    `/reviews/${applicant.id}/decision`,
    reviewer.token,
    {
      submissionId: inspected.body.submissionId,
      decision: "rejected",
      reason: "Retake legacy selfie",
      requiredSteps: ["selfie"],
    },
  );
  assert.equal(rejected.status, 200);
  const archived = await history(applicant);
  assert.equal(archived.total, 1);
  const first = archived.submissions[0]!;
  assertSubmission(first, 1);
  assert.deepEqual(first.profile.personalDetails, details);
  assert.deepEqual(first.profile.document, pending.body.profile.document);
  assert.deepEqual(first.profile.selfie, pending.body.profile.selfie);
  assert.equal(first.profile.submittedAt, "2026-01-02T03:04:05.000Z");
  assert.equal(first.profile.status, "rejected");
  assert.equal(first.review!.reviewer!.id, reviewer.id);
  assert.equal(
    (await json("POST", "/kyc/resubmit", applicant.token)).status,
    200,
  );
  assert.deepEqual(await history(applicant, reviewer), archived);
  for (const kind of ["document", "selfie"] as const) {
    await assertArchivedPhoto(
      applicant,
      first.id,
      kind,
      originalImage,
      reviewer,
    );
  }
});

test("legacy rejected profiles are archived before reopening even without a recorded reviewer", async () => {
  const applicant = await actor("legacy-rejected-history");
  await legacyProfile(applicant, "rejected");
  const rejected = await json("GET", "/kyc", applicant.token);
  assert.equal(
    (await json("POST", "/kyc/resubmit", applicant.token)).status,
    200,
  );
  const archived = await history(applicant);
  assert.equal(archived.total, 1);
  const first = archived.submissions[0]!;
  assertSubmission(first, 1);
  assert.deepEqual(first.profile, rejected.body.profile);
  for (const kind of ["document", "selfie"] as const) {
    await assertArchivedPhoto(applicant, first.id, kind, originalImage);
  }
});
