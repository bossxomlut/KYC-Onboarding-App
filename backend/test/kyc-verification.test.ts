import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, test } from "node:test";
import EmbeddedPostgres from "embedded-postgres";
import { Pool } from "pg";
import sharp from "sharp";
import request from "supertest";
import { buildApp } from "../src/app.js";
import type { Config } from "../src/config.js";
import { migrate } from "../src/database.js";
import { accessToken, decrypt, encrypt } from "../src/security.js";
import { getProfile } from "../src/kyc/kyc.repository.js";
import type { IdentityCheckResult } from "../src/verification/identity-verifier.js";

let directory: string;
let postgres: EmbeddedPostgres;
let pool: Pool;
let app: Awaited<ReturnType<typeof buildApp>>;
let config: Config;
let image: Buffer;
const calls: { document: Buffer; selfie: Buffer }[] = [];
const successful = {
  ocr: {
    status: "succeeded" as const,
    text: "SYNTHETIC DOCUMENT TEXT 123456",
    fields: {
      fullName: "Synthetic Applicant",
      dateOfBirth: "1990-01-01",
      documentNumber: "SYNTHETIC123",
    },
    confidence: 98,
  },
  selfieFace: { status: "detected" as const },
  faceMatch: { status: "matched" as const, similarity: 99, threshold: 90 },
};
let verifyImpl: () => Promise<IdentityCheckResult> = async () => successful;
const verifier = {
  verify: async (document: Buffer, selfie: Buffer) => {
    calls.push({ document, selfie });
    return verifyImpl();
  },
};
const details = {
  fullName: "Synthetic Applicant",
  dateOfBirth: "1990-01-01",
  nationality: "VN",
  address: "123 Synthetic Street, Demo City",
  documentNumber: "SYNTHETIC123",
};
type Actor = { id: string; token: string };

before(async () => {
  directory = await mkdtemp(join(tmpdir(), "kyc-verification-test-"));
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
    rateLimitMax: 1000,
    maxUploadBytes: 10 * 1024 * 1024,
    verification: {
      provider: "aws",
      region: "ap-southeast-1",
      faceMatchThreshold: 90,
      timeoutMs: 7000,
    },
  };
  app = await buildApp(config, pool, { send: async () => {} }, verifier);
  image = await sharp({
    create: { width: 48, height: 32, channels: 3, background: "#125773" },
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
async function actor(role = "user"): Promise<Actor> {
  const id = randomUUID();
  const sessionId = randomUUID();
  await pool.query(
    "INSERT INTO users(id,email_normalized,password_hash,email_verified_at,status,role) VALUES($1,$2,'test-only',now(),'active',$3)",
    [id, `${id}@example.test`, role],
  );
  await pool.query("INSERT INTO kyc_profiles(id,user_id) VALUES($1,$2)", [
    randomUUID(),
    id,
  ]);
  await pool.query(
    "INSERT INTO auth_sessions(id,user_id,family_id,refresh_token_hash,expires_at) VALUES($1,$2,$3,$4,now()+interval '1 day')",
    [sessionId, id, randomUUID(), randomUUID()],
  );
  return { id, token: await accessToken(id, sessionId, config) };
}
function json(
  method: "get" | "post" | "put",
  path: string,
  user?: Actor,
  body?: object,
  application = app,
) {
  let call = request(application.getHttpServer())[method](`/api/v1${path}`);
  if (user) call = call.set("authorization", `Bearer ${user.token}`);
  if (body) call = call.send(body);
  return call;
}
async function upload(
  user: Actor,
  kind: "document" | "selfie",
  captureId = `verification-${randomUUID()}`,
) {
  let call = request(app.getHttpServer())
    .post(`/api/v1/kyc/media/${kind}`)
    .set("authorization", `Bearer ${user.token}`)
    .field("captureId", captureId);
  if (kind === "document") call = call.field("documentType", "passport");
  const response = await call.attach("file", image, {
    filename: "synthetic.jpg",
    contentType: "image/jpeg",
  });
  assert.equal(response.status, 200);
  return response;
}
async function draft(user: Actor) {
  assert.equal(
    (await json("put", "/kyc/personal-details", user, details)).status,
    200,
  );
  await upload(user, "document");
  await upload(user, "selfie");
}
async function check(user: Actor) {
  return json("post", "/kyc/verification", user);
}

test("verification requires authentication, both owned images and configured provider", async () => {
  assert.equal((await json("post", "/kyc/verification")).status, 401);
  const user = await actor();
  assert.equal(
    (await check(user)).body.error.code,
    "KYC_VERIFICATION_INCOMPLETE",
  );
  await draft(user);
  const disabledConfig = { ...config, verification: undefined };
  const disabled = await buildApp(
    disabledConfig,
    pool,
    { send: async () => {} },
    null,
  );
  try {
    assert.equal(
      (await json("post", "/kyc/verification", user, undefined, disabled)).body
        .error.code,
      "VERIFICATION_NOT_CONFIGURED",
    );
    const profile = (await json("get", "/kyc", user, undefined, disabled)).body
      .profile;
    assert.equal(profile.verification.provider, "none");
    assert.equal(profile.verification.status, "disabled");
  } finally {
    await disabled.close();
  }
});

test("verification persists encrypted evidence tied to media IDs and caches completed checks", async () => {
  verifyImpl = async () => successful;
  const user = await actor();
  await draft(user);
  const beforeCalls = calls.length;
  const checked = await check(user);
  assert.equal(checked.status, 200);
  const profile = checked.body.profile;
  assert.equal(profile.status, "in_progress");
  assert.equal(profile.verification.status, "completed");
  assert.equal(profile.verification.documentId, profile.document.id);
  assert.equal(profile.verification.selfieId, profile.selfie.id);
  assert.deepEqual(profile.verification.ocr, successful.ocr);
  assert.deepEqual(profile.verification.selfieFace, successful.selfieFace);
  assert.deepEqual(profile.verification.faceMatch, successful.faceMatch);
  assert.equal(calls.length, beforeCalls + 1);
  assert.equal(calls.at(-1)!.document.subarray(0, 3).toString("hex"), "ffd8ff");
  const row = (
    await pool.query("SELECT verification FROM kyc_profiles WHERE user_id=$1", [
      user.id,
    ])
  ).rows[0];
  assert.equal(typeof row.verification, "string");
  assert.equal(row.verification.includes(successful.ocr.text), false);
  assert.equal(
    row.verification.includes(successful.ocr.fields.documentNumber),
    false,
  );
  assert.deepEqual(
    (await check(user)).body.profile.verification,
    profile.verification,
  );
  assert.equal(calls.length, beforeCalls + 1);
  assert.deepEqual(
    (await json("get", "/kyc", user)).body.profile.verification,
    profile.verification,
  );
  const other = await actor();
  assert.equal(
    (await json("get", "/kyc", other)).body.profile.verification.status,
    "not_started",
  );
  assert.equal(
    (await check(other)).body.error.code,
    "KYC_VERIFICATION_INCOMPLETE",
  );
});

test("capture retries preserve verification; real replacement invalidates; details edits preserve", async () => {
  const user = await actor();
  await draft(user);
  const captureId = `verification-${randomUUID()}`;
  await upload(user, "selfie", captureId);
  const verification = (await check(user)).body.profile.verification;
  assert.deepEqual(
    (await upload(user, "selfie", captureId)).body.profile.verification,
    verification,
  );
  const edited = await json("put", "/kyc/personal-details", user, {
    ...details,
    fullName: "Updated Synthetic Name",
  });
  assert.deepEqual(edited.body.profile.verification, verification);
  const replacement = await upload(user, "selfie");
  assert.equal(replacement.body.profile.verification.status, "not_started");
  assert.equal(replacement.body.profile.verification.ocr, null);
  assert.equal(
    (await check(user)).body.error.code,
    "KYC_VERIFICATION_RATE_LIMITED",
  );
});

test("editable profiles rerun checks when provider or matching threshold changes, while snapshots retain original evidence", async () => {
  verifyImpl = async () => successful;
  const user = await actor();
  await draft(user);
  const original = (await check(user)).body.profile.verification;
  assert.equal(original.provider, "aws");
  const beforeCalls = calls.length;
  const localConfig: Config = {
    ...config,
    verification: {
      provider: "local",
      pythonPath: "/test/python",
      modelsDir: "/test/models",
      ocrLanguages: "vie",
      faceMatchThreshold: 36.3,
      timeoutMs: 7000,
    },
  };
  const local = await buildApp(
    localConfig,
    pool,
    { send: async () => {} },
    {
      verify: async () => {
        calls.push({ document: image, selfie: image });
        return {
          ...successful,
          faceMatch: { ...successful.faceMatch, threshold: 36.3 },
        };
      },
    },
  );
  try {
    const current = (await json("get", "/kyc", user, undefined, local)).body
      .profile.verification;
    assert.equal(current.provider, "local");
    assert.equal(current.status, "not_started");
    assert.equal(current.ocr, null);
    await pool.query(
      "UPDATE kyc_profiles SET verification_started_at=now()-interval '31 seconds' WHERE user_id=$1",
      [user.id],
    );
    const result = await json(
      "post",
      "/kyc/verification",
      user,
      undefined,
      local,
    );
    assert.equal(result.status, 200);
    assert.equal(result.body.profile.verification.provider, "local");
    assert.equal(result.body.profile.verification.faceMatch.threshold, 36.3);
    assert.equal(calls.length, beforeCalls + 1);
    assert.equal(
      (await json("post", "/kyc/submit", user, undefined, local)).status,
      200,
    );
    const history = await json("get", "/kyc/history", user);
    assert.equal(
      history.body.submissions[0].profile.verification.provider,
      "local",
    );
    assert.equal(
      history.body.submissions[0].profile.verification.faceMatch.threshold,
      36.3,
    );
  } finally {
    await local.close();
  }

  const second = await actor();
  await draft(second);
  await check(second);
  const changedConfig: Config = {
    ...config,
    verification: {
      provider: "aws",
      region: "ap-southeast-1",
      faceMatchThreshold: 95,
      timeoutMs: 7000,
    },
  };
  const changed = await buildApp(
    changedConfig,
    pool,
    { send: async () => {} },
    {
      verify: async () => ({
        ...successful,
        faceMatch: { ...successful.faceMatch, threshold: 95 },
      }),
    },
  );
  try {
    const current = (await json("get", "/kyc", second, undefined, changed)).body
      .profile.verification;
    assert.equal(current.status, "not_started");
    await pool.query(
      "UPDATE kyc_profiles SET verification_started_at=now()-interval '31 seconds' WHERE user_id=$1",
      [second.id],
    );
    const result = await json(
      "post",
      "/kyc/verification",
      second,
      undefined,
      changed,
    );
    assert.equal(result.status, 200);
    assert.equal(result.body.profile.verification.faceMatch.threshold, 95);
  } finally {
    await changed.close();
  }
});

test("changing local OCR language invalidates draft evidence and reruns, while submission history keeps its original language", async () => {
  const user = await actor();
  await draft(user);
  let localCalls = 0;
  const configured = (ocrLanguages: "vie" | "eng"): Config => ({
    ...config,
    verification: {
      provider: "local",
      pythonPath: "/test/python",
      modelsDir: "/test/models",
      ocrLanguages,
      faceMatchThreshold: 36.3,
      timeoutMs: 7000,
    },
  });
  const localVerifier = {
    verify: async () => {
      localCalls++;
      return {
        ...successful,
        faceMatch: { ...successful.faceMatch, threshold: 36.3 },
      };
    },
  };
  const vietnamese = await buildApp(
    configured("vie"),
    pool,
    { send: async () => {} },
    localVerifier,
  );
  const english = await buildApp(
    configured("eng"),
    pool,
    { send: async () => {} },
    localVerifier,
  );
  try {
    const first = await json(
      "post",
      "/kyc/verification",
      user,
      undefined,
      vietnamese,
    );
    assert.equal(first.status, 200);
    assert.equal(first.body.profile.verification.ocrLanguages, "vie");
    await json("post", "/kyc/verification", user, undefined, vietnamese);
    assert.equal(localCalls, 1);
    const current = (await json("get", "/kyc", user, undefined, english)).body
      .profile.verification;
    assert.equal(current.status, "not_started");
    assert.equal(current.ocr, null);
    await pool.query(
      "UPDATE kyc_profiles SET verification_started_at=now()-interval '31 seconds' WHERE user_id=$1",
      [user.id],
    );
    const changed = await json(
      "post",
      "/kyc/verification",
      user,
      undefined,
      english,
    );
    assert.equal(changed.status, 200);
    assert.equal(changed.body.profile.verification.ocrLanguages, "eng");
    assert.equal(localCalls, 2);
    assert.equal(
      (await json("post", "/kyc/submit", user, undefined, english)).status,
      200,
    );
    const history = (
      await json("get", "/kyc/history", user, undefined, vietnamese)
    ).body;
    assert.equal(
      history.submissions[0].profile.verification.ocrLanguages,
      "eng",
    );
  } finally {
    await vietnamese.close();
    await english.close();
  }
});

test("a profile read overlapping media replacement never pairs old verification with the new photos", async () => {
  verifyImpl = async () => successful;
  const user = await actor();
  await draft(user);
  const previous = (await check(user)).body.profile;
  // Both queries use real PostgreSQL. Pause after the first read to schedule
  // the same HTTP replacement that can occur during an ordinary GET.
  const overlappingRead = {
    query: async (sql: string, values: unknown[]) => {
      const rows = await pool.query(sql, values);
      if (sql === "SELECT * FROM kyc_profiles WHERE user_id=$1")
        await upload(user, "selfie");
      return rows;
    },
  } as unknown as Pool;
  const profile = await getProfile(overlappingRead, user.id, config);
  assert.notEqual(profile.selfie?.id, previous.selfie.id);
  assert.equal(profile.verification.status, "not_started");
  assert.equal(profile.verification.ocr, null);
});

test("provider failures reveal no provider secrets and retry uses a durable cooldown", async () => {
  const user = await actor();
  await draft(user);
  verifyImpl = async () => {
    throw new Error("SECRET-CLOUD-PAYLOAD-SYNTHETIC123");
  };
  const failed = await check(user);
  assert.equal(failed.status, 200);
  assert.equal(failed.body.profile.verification.status, "failed");
  assert.equal(failed.text.includes("SECRET-CLOUD-PAYLOAD"), false);
  assert.equal(
    (await check(user)).body.error.code,
    "KYC_VERIFICATION_RATE_LIMITED",
  );
  await pool.query(
    "UPDATE kyc_profiles SET verification_started_at=now()-interval '31 seconds' WHERE user_id=$1",
    [user.id],
  );
  verifyImpl = async () => successful;
  assert.equal(
    (await check(user)).body.profile.verification.status,
    "completed",
  );
});

test("in-flight checks coalesce through DB guard, block submit and discard replaced-media results", async () => {
  const user = await actor();
  await draft(user);
  let finish!: (value: IdentityCheckResult) => void;
  let started!: () => void;
  const start = new Promise<void>((resolve) => {
    started = resolve;
  });
  verifyImpl = () => {
    started();
    return new Promise((resolve) => {
      finish = resolve;
    });
  };
  const pending = check(user).then((value) => value);
  await start;
  assert.equal(
    (await check(user)).body.error.code,
    "KYC_VERIFICATION_IN_PROGRESS",
  );
  assert.equal(
    (await json("post", "/kyc/submit", user)).body.error.code,
    "KYC_VERIFICATION_IN_PROGRESS",
  );
  await upload(user, "selfie");
  finish(successful);
  assert.equal((await pending).body.error.code, "KYC_VERIFICATION_CHANGED");
  assert.equal(
    (await json("get", "/kyc", user)).body.profile.verification.status,
    "not_started",
  );
  verifyImpl = async () => successful;
});

test("expired attempts recover and an older completion cannot overwrite a newer check", async () => {
  const user = await actor();
  await draft(user);
  let finish!: (value: IdentityCheckResult) => void;
  let started!: () => void;
  const start = new Promise<void>((resolve) => {
    started = resolve;
  });
  verifyImpl = () => {
    started();
    return new Promise((resolve) => {
      finish = resolve;
    });
  };
  const oldRequest = check(user).then((value) => value);
  await start;
  await pool.query(
    "UPDATE kyc_profiles SET verification_started_at=now()-interval '31 seconds' WHERE user_id=$1",
    [user.id],
  );
  verifyImpl = async () => successful;
  const current = await check(user);
  assert.equal(current.status, 200);
  finish({
    ...successful,
    faceMatch: { status: "not_matched", similarity: 12, threshold: 90 },
  });
  assert.equal((await oldRequest).body.error.code, "KYC_VERIFICATION_CHANGED");
  assert.deepEqual(
    (await json("get", "/kyc", user)).body.profile.verification,
    current.body.profile.verification,
  );

  const abandoned = await actor();
  await draft(abandoned);
  await pool.query(
    "UPDATE kyc_profiles SET verification_attempt_id=$2,verification_started_at=now()-interval '9 seconds' WHERE user_id=$1",
    [abandoned.id, randomUUID()],
  );
  assert.equal((await json("post", "/kyc/submit", abandoned)).status, 200);
});

test("partial provider failures preserve successful OCR; semantic mismatch still permits manual review", async () => {
  const partial = await actor();
  await draft(partial);
  verifyImpl = async () => ({
    ...successful,
    faceMatch: { status: "failed", similarity: null, threshold: 90 },
  });
  const failed = await check(partial);
  assert.equal(failed.body.profile.verification.status, "failed");
  assert.deepEqual(failed.body.profile.verification.ocr, successful.ocr);
  assert.deepEqual(
    failed.body.profile.verification.selfieFace,
    successful.selfieFace,
  );
  assert.equal((await json("post", "/kyc/submit", partial)).status, 200);

  const mismatch = await actor();
  await draft(mismatch);
  verifyImpl = async () => ({
    ...successful,
    faceMatch: { status: "multiple_faces", similarity: null, threshold: 90 },
  });
  const completed = await check(mismatch);
  assert.equal(completed.body.profile.verification.status, "completed");
  assert.equal(
    (await json("post", "/kyc/submit", mismatch)).body.profile.status,
    "pending_review",
  );
  verifyImpl = async () => successful;
});

test("selfie detection is persisted independently when the document has no face", async () => {
  const user = await actor();
  await draft(user);
  verifyImpl = async () => ({
    ...successful,
    faceMatch: { status: "no_face", similarity: null, threshold: 90 },
  });
  const checked = await check(user);
  assert.equal(checked.status, 200);
  assert.equal(checked.body.profile.verification.status, "completed");
  assert.deepEqual(checked.body.profile.verification.selfieFace, {
    status: "detected",
  });
  assert.equal(checked.body.profile.verification.faceMatch.status, "no_face");
  const submitted = await json("post", "/kyc/submit", user);
  assert.equal(submitted.status, 200);
  const history = await json("get", "/kyc/history", user);
  assert.deepEqual(
    history.body.submissions[0].profile.verification.selfieFace,
    { status: "detected" },
  );
  verifyImpl = async () => successful;
});

test("legacy evidence has no invented selfie check and editable profiles rerun once", async () => {
  const user = await actor();
  await draft(user);
  verifyImpl = async () => successful;
  await check(user);
  const stored = (
    await pool.query("SELECT verification FROM kyc_profiles WHERE user_id=$1", [
      user.id,
    ])
  ).rows[0].verification;
  const legacy = JSON.parse(
    decrypt(Buffer.from(stored, "base64"), config.mediaKey).toString("utf8"),
  );
  delete legacy.selfieFace;
  const legacyEncrypted = encrypt(
    Buffer.from(JSON.stringify(legacy)),
    config.mediaKey,
  ).toString("base64");
  await pool.query(
    "UPDATE kyc_profiles SET verification=$2,verification_started_at=now()-interval '31 seconds' WHERE user_id=$1",
    [user.id, legacyEncrypted],
  );
  const current = (await json("get", "/kyc", user)).body.profile.verification;
  assert.equal(current.status, "not_started");
  assert.equal(current.selfieFace, null);
  const beforeCalls = calls.length;
  const refreshed = await check(user);
  assert.equal(refreshed.status, 200);
  assert.deepEqual(refreshed.body.profile.verification.selfieFace, {
    status: "detected",
  });
  assert.equal(calls.length, beforeCalls + 1);

  await json("post", "/kyc/submit", user);
  await pool.query(
    "UPDATE kyc_submissions SET verification=$2 WHERE user_id=$1",
    [user.id, legacyEncrypted],
  );
  const history = await json("get", "/kyc/history", user);
  const old = history.body.submissions[0].profile.verification;
  assert.equal(old.status, "completed");
  assert.equal(old.selfieFace, null);
  assert.deepEqual(old.faceMatch, successful.faceMatch);
});

test("verification snapshots survive manual rejection, resubmission and later checks", async () => {
  const user = await actor();
  const reviewer = await actor("reviewer");
  await draft(user);
  const verification = (await check(user)).body.profile.verification;
  const submitted = await json("post", "/kyc/submit", user);
  assert.equal(submitted.status, 200);
  assert.equal((await check(user)).body.error.code, "KYC_LOCKED");
  const detail = await json("get", `/reviews/${user.id}`, reviewer);
  assert.deepEqual(detail.body.profile.verification, verification);
  assert.equal(
    (
      await json("post", `/reviews/${user.id}/decision`, reviewer, {
        submissionId: detail.body.submissionId,
        decision: "rejected",
        reason: "Retake selfie",
        requiredSteps: ["selfie"],
      })
    ).status,
    200,
  );
  const reopened = await json("post", "/kyc/resubmit", user);
  assert.equal(reopened.body.profile.verification.status, "not_started");
  await upload(user, "selfie");
  await check(user);
  const history = await json("get", "/kyc/history", user);
  assert.deepEqual(
    history.body.submissions[0].profile.verification,
    verification,
  );
  const reviewHistory = await json(
    "get",
    `/reviews/${user.id}/history`,
    reviewer,
  );
  assert.deepEqual(
    reviewHistory.body.submissions[0].profile.verification,
    verification,
  );
  const snapshot = (
    await pool.query("SELECT verification FROM kyc_submissions WHERE id=$1", [
      detail.body.submissionId,
    ])
  ).rows[0].verification;
  assert.equal(snapshot.includes(successful.ocr.text), false);
});

test("resubmission requesting only details preserves image verification", async () => {
  const user = await actor();
  const reviewer = await actor("reviewer");
  await draft(user);
  const verification = (await check(user)).body.profile.verification;
  await json("post", "/kyc/submit", user);
  const detail = await json("get", `/reviews/${user.id}`, reviewer);
  await json("post", `/reviews/${user.id}/decision`, reviewer, {
    submissionId: detail.body.submissionId,
    decision: "rejected",
    reason: "Correct address",
    requiredSteps: ["personal_details"],
  });
  assert.deepEqual(
    (await json("post", "/kyc/resubmit", user)).body.profile.verification,
    verification,
  );
});
