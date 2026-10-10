import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import { mkdtemp, rm, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { randomBytes } from "node:crypto";
import EmbeddedPostgres from "embedded-postgres";
import { Pool } from "pg";
import sharp from "sharp";
import { buildApp } from "../src/app.js";
import { migrate } from "../src/database.js";
import { reviewProfile } from "../src/kyc.js";
import type { Config } from "../src/config.js";
import type { Mail } from "../src/mail.js";
import { deliverQueued } from "../src/mail.js";

let directory: string;
let postgres: EmbeddedPostgres;
let pool: Pool;
let app: Awaited<ReturnType<typeof buildApp>>;
let image: Buffer;
const mails: Mail[] = [];
const email = "alice@example.test";
const password = "SyntheticPass123!";
let session: {
  accessToken: string;
  refreshToken: string;
  user: { id: string };
};
let config: Config;

before(async () => {
  directory = await mkdtemp(join(tmpdir(), "kyc-api-test-"));
  postgres = new EmbeddedPostgres({
    databaseDir: join(directory, "postgres"),
    port: 55439,
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
      "postgresql://postgres:test-only@localhost:55439/postgres",
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
  app = await buildApp(config, pool, {
    send: async (mail) => {
      mails.push(mail);
    },
  });
  image = await sharp({
    create: { width: 80, height: 60, channels: 3, background: "#026220" },
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
  method: "POST" | "GET" | "PUT",
  path: string,
  body?: unknown,
  token?: string,
) {
  return app.inject({
    method,
    url: `/api/v1${path}`,
    headers: token ? { authorization: `Bearer ${token}` } : {},
    payload: body as any,
  });
}
async function upload(
  kind: string,
  bytes: Buffer = image,
  token = session.accessToken,
  captureId?: string,
) {
  const boundary = "synthetic-test-boundary";
  const content = Buffer.concat([
    Buffer.from(
      captureId
        ? `--${boundary}\r\nContent-Disposition: form-data; name="captureId"\r\n\r\n${captureId}\r\n`
        : "",
    ),
    Buffer.from(
      `--${boundary}\r\nContent-Disposition: form-data; name="documentType"\r\n\r\npassport\r\n--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="demo.jpg"\r\nContent-Type: image/jpeg\r\n\r\n`,
    ),
    bytes,
    Buffer.from(`\r\n--${boundary}--\r\n`),
  ]);
  return app.inject({
    method: "POST",
    url: `/api/v1/kyc/media/${kind}`,
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": `multipart/form-data; boundary=${boundary}`,
    },
    payload: content,
  });
}

test("registration, wrong/expired OTP, verification, and login restrictions", async () => {
  const register = await json("POST", "/auth/register", { email, password });
  assert.equal(register.statusCode, 201);
  assert.equal(register.json().user.emailVerified, false);
  assert.equal(
    (await json("POST", "/auth/login", { email, password })).json().error.code,
    "EMAIL_NOT_VERIFIED",
  );
  assert.equal(
    (
      await json("POST", "/auth/login", { email, password: "wrongPassword1!" })
    ).json().error.code,
    "INVALID_CREDENTIALS",
  );
  assert.equal(
    (await json("POST", "/auth/email/verify", { email, code: "000000" })).json()
      .error.code,
    "OTP_INVALID",
  );
  const otp = mails.at(-1)!.text.match(/\b\d{6}\b/)![0];
  await pool.query(
    "UPDATE email_verification_tokens SET expires_at=now()-interval '1 second'",
  );
  assert.equal(
    (await json("POST", "/auth/email/verify", { email, code: otp })).json()
      .error.code,
    "OTP_EXPIRED",
  );
  await pool.query(
    "UPDATE email_verification_tokens SET expires_at=now()+interval '10 minutes'",
  );
  const verify = await json("POST", "/auth/email/verify", { email, code: otp });
  assert.equal(verify.statusCode, 200);
  session = verify.json();
  assert.equal(session.user.id.length, 36);
  assert.equal(
    (await json("POST", "/auth/email/verify", { email, code: otp })).statusCode,
    400,
  );
  assert.equal(
    (await json("GET", "/auth/me", undefined, session.accessToken)).statusCode,
    200,
  );
});

test("refresh rotates atomically; replay revokes the family; logout revokes access and refresh", async () => {
  const old = session.refreshToken;
  const refresh = await json("POST", "/auth/refresh", { refreshToken: old });
  assert.equal(refresh.statusCode, 200);
  session = refresh.json();
  assert.notEqual(session.refreshToken, old);
  assert.equal(
    (await json("POST", "/auth/refresh", { refreshToken: old })).json().error
      .code,
    "SESSION_EXPIRED",
  );
  assert.equal(
    (
      await json("POST", "/auth/refresh", {
        refreshToken: session.refreshToken,
      })
    ).statusCode,
    401,
  );
  session = (await json("POST", "/auth/login", { email, password })).json();
  assert.equal(
    (await json("POST", "/auth/logout", { refreshToken: session.refreshToken }))
      .statusCode,
    200,
  );
  assert.equal(
    (await json("GET", "/auth/me", undefined, session.accessToken)).statusCode,
    401,
  );
  assert.equal(
    (
      await json("POST", "/auth/refresh", {
        refreshToken: session.refreshToken,
      })
    ).statusCode,
    401,
  );
  session = (await json("POST", "/auth/login", { email, password })).json();
});

test("concurrent refresh creates one successor and replay revokes it; stale-token logout revokes successor", async () => {
  const responses = await Promise.all([
    json("POST", "/auth/refresh", { refreshToken: session.refreshToken }),
    json("POST", "/auth/refresh", { refreshToken: session.refreshToken }),
  ]);
  assert.deepEqual(responses.map((item) => item.statusCode).sort(), [200, 401]);
  const next = responses.find((item) => item.statusCode === 200)!.json();
  assert.equal(
    (await json("GET", "/auth/me", undefined, next.accessToken)).statusCode,
    401,
  );
  session = (await json("POST", "/auth/login", { email, password })).json();
  const ancestor = session.refreshToken;
  session = (
    await json("POST", "/auth/refresh", { refreshToken: ancestor })
  ).json();
  await json("POST", "/auth/logout", { refreshToken: ancestor });
  assert.equal(
    (await json("GET", "/auth/me", undefined, session.accessToken)).statusCode,
    401,
  );
  session = (await json("POST", "/auth/login", { email, password })).json();
});

test("OTP attempt limit persists and prevents a correct code after five wrong attempts", async () => {
  const candidate = "attempts@example.test";
  await json("POST", "/auth/register", { email: candidate, password });
  const code = mails.at(-1)!.text.match(/\b\d{6}\b/)![0];
  for (let count = 0; count < 5; count++)
    assert.equal(
      (
        await json("POST", "/auth/email/verify", {
          email: candidate,
          code: "000000",
        })
      ).statusCode,
      400,
    );
  assert.equal(
    (
      await json("POST", "/auth/email/verify", { email: candidate, code })
    ).json().error.code,
    "OTP_INVALID",
  );
  const stored = await pool.query(
    "SELECT attempt_count FROM email_verification_tokens t JOIN users u ON u.id=t.user_id WHERE u.email_normalized=$1",
    [candidate],
  );
  assert.equal(stored.rows[0].attempt_count, 5);
});

test("reset is generic, expiring and single-use; resets revoke all sessions", async () => {
  const unknown = await json("POST", "/auth/password/forgot", {
    email: "unknown@example.test",
  });
  const known = await json("POST", "/auth/password/forgot", { email });
  assert.deepEqual(unknown.json(), known.json());
  assert.equal(
    await deliverQueued(pool, config, {
      send: async (mail) => {
        mails.push(mail);
      },
    }),
    true,
  );
  const token = mails.at(-1)!.text.match(/token=([^\s]+)/)![1]!;
  assert.equal(
    (
      await json("POST", "/auth/password/reset", {
        token: "invalid",
        newPassword: password,
      })
    ).json().error.code,
    "RESET_TOKEN_INVALID",
  );
  await pool.query(
    "UPDATE password_reset_tokens SET expires_at=now()-interval '1 second'",
  );
  assert.equal(
    (
      await json("POST", "/auth/password/reset", {
        token,
        newPassword: password,
      })
    ).statusCode,
    400,
  );
  await pool.query(
    "UPDATE password_reset_tokens SET expires_at=now()+interval '10 minutes'",
  );
  assert.equal(
    (
      await json("POST", "/auth/password/reset", {
        token,
        newPassword: "ReplacementPass123!",
      })
    ).statusCode,
    200,
  );
  assert.equal(
    (
      await json("POST", "/auth/password/reset", {
        token,
        newPassword: password,
      })
    ).statusCode,
    400,
  );
  assert.equal(
    (await json("GET", "/auth/me", undefined, session.accessToken)).statusCode,
    401,
  );
  assert.equal(
    (await json("POST", "/auth/login", { email, password })).statusCode,
    401,
  );
  session = (
    await json("POST", "/auth/login", {
      email,
      password: "ReplacementPass123!",
    })
  ).json();
});

test("KYC validates details and media, keeps private encrypted storage, and resumes saved progress", async () => {
  assert.equal((await json("GET", "/kyc")).statusCode, 401);
  assert.equal(
    (await json("GET", "/kyc", undefined, session.accessToken)).json().profile
      .status,
    "not_started",
  );
  assert.equal(
    (await json("POST", "/kyc/submit", {}, session.accessToken)).json().error
      .code,
    "KYC_INCOMPLETE",
  );
  assert.equal(
    (
      await json(
        "PUT",
        "/kyc/personal-details",
        { fullName: "x" },
        session.accessToken,
      )
    ).statusCode,
    400,
  );
  const details = {
    fullName: "Synthetic Alice",
    dateOfBirth: "1990-01-01",
    nationality: "VN",
    address: "123 Example Street, Demo City",
    documentNumber: "DEMO-123456",
  };
  const saved = await json(
    "PUT",
    "/kyc/personal-details",
    details,
    session.accessToken,
  );
  assert.equal(saved.statusCode, 200);
  assert.equal(saved.json().profile.nextStep, "document");
  assert.equal(
    (await upload("document", Buffer.from("not an image"))).statusCode,
    400,
  );
  assert.equal(
    (await upload("document", Buffer.alloc(config.maxUploadBytes + 1, 0)))
      .statusCode,
    413,
  );
  assert.equal((await upload("document")).statusCode, 200);
  const captureId = randomBytes(16).toString("hex");
  const captured = await upload(
    "document",
    image,
    session.accessToken,
    captureId,
  );
  assert.equal(captured.json().profile.document.captureId, captureId);
  const replay = await upload(
    "document",
    image,
    session.accessToken,
    captureId,
  );
  assert.equal(
    replay.json().profile.document.id,
    captured.json().profile.document.id,
  );
  assert.equal((await upload("selfie")).statusCode, 200);
  const profile = (
    await json("GET", "/kyc", undefined, session.accessToken)
  ).json().profile;
  assert.equal(profile.nextStep, "review");
  assert.deepEqual(profile.personalDetails, details);
  const media = await json(
    "GET",
    "/kyc/media/document",
    undefined,
    session.accessToken,
  );
  assert.equal(media.statusCode, 200);
  assert.equal(media.headers["content-type"], "image/jpeg");
  assert.equal(media.headers["cache-control"], "no-store");
  const records = await pool.query(
    "SELECT personal_details FROM kyc_profiles WHERE user_id=$1",
    [session.user.id],
  );
  assert.equal(
    records.rows[0].personal_details.includes("Synthetic Alice"),
    false,
  );
  const asset = await pool.query(
    "SELECT storage_key FROM kyc_media WHERE user_id=$1 AND kind='document'",
    [session.user.id],
  );
  const disk = await readFile(join(config.mediaDir, asset.rows[0].storage_key));
  assert.notDeepEqual(disk.subarray(0, 3), Buffer.from([255, 216, 255]));
});

test("cross-user access is isolated; submit/reject/resubmit only clears rejected assets and verified locks data", async () => {
  const second = "bob@example.test";
  await json("POST", "/auth/register", { email: second, password });
  const code = mails.at(-1)!.text.match(/\b\d{6}\b/)![0];
  const bob = (
    await json("POST", "/auth/email/verify", { email: second, code })
  ).json();
  const own = (await json("GET", "/kyc", undefined, bob.accessToken)).json()
    .profile;
  assert.equal(own.personalDetails, null);
  assert.equal(own.document, null);
  assert.equal(
    (await json("GET", "/kyc/media/document", undefined, bob.accessToken))
      .statusCode,
    404,
  );
  assert.equal(
    (await json("GET", `/kyc/${session.user.id}`, undefined, bob.accessToken))
      .statusCode,
    404,
  );
  const submit = await json("POST", "/kyc/submit", {}, session.accessToken);
  assert.equal(submit.statusCode, 200);
  assert.equal(submit.json().profile.status, "pending_review");
  assert.equal((await upload("selfie")).statusCode, 409);
  await reviewProfile(
    pool,
    session.user.id,
    "rejected",
    "Synthetic selfie needs retaking",
    ["selfie"],
  );
  let rejected = (
    await json("GET", "/kyc", undefined, session.accessToken)
  ).json().profile;
  assert.equal(rejected.status, "rejected");
  assert.deepEqual(rejected.requiredSteps, ["selfie"]);
  assert.equal((await upload("selfie")).statusCode, 409);
  const resume = await json("POST", "/kyc/resubmit", {}, session.accessToken);
  assert.equal(resume.statusCode, 200);
  rejected = resume.json().profile;
  assert.equal(rejected.status, "in_progress");
  assert.equal(rejected.nextStep, "selfie");
  assert.ok(rejected.personalDetails);
  assert.ok(rejected.document);
  assert.equal(rejected.selfie, null);
  assert.equal((await upload("selfie")).statusCode, 200);
  await json("POST", "/kyc/submit", {}, session.accessToken);
  await reviewProfile(pool, session.user.id, "verified");
  const verified = (
    await json("GET", "/kyc", undefined, session.accessToken)
  ).json().profile;
  assert.equal(verified.status, "verified");
  assert.equal(verified.nextStep, "result");
  assert.equal(
    (await json("POST", "/kyc/resubmit", {}, session.accessToken)).statusCode,
    409,
  );
});

test("auth route rate limits and SMTP failures return safe recoverable errors", async () => {
  const limited = await buildApp({ ...config, rateLimitMax: 2 }, pool, {
    send: async () => {
      throw new Error("private SMTP configuration");
    },
  });
  const request = () =>
    limited.inject({
      method: "POST",
      url: "/api/v1/auth/register",
      payload: { email: "mailfail@example.test", password },
    });
  const response = await request();
  assert.equal(response.statusCode, 503);
  assert.equal(response.json().error.code, "EMAIL_DELIVERY_FAILED");
  assert.equal(response.body.includes("private SMTP"), false);
  await request();
  const exhausted = await request();
  assert.equal(exhausted.statusCode, 429);
  assert.equal(exhausted.json().error.code, "RATE_LIMITED");
  assert.ok(exhausted.json().error.requestId);
  await limited.close();
});

test("forgot/resend stay generic during SMTP outage and encrypted outbox retries after recovery", async () => {
  const failing = await buildApp(config, pool, {
    send: async () => {
      throw new Error("secret SMTP failure");
    },
  });
  const post = (path: string, payload: unknown) =>
    failing.inject({
      method: "POST",
      url: `/api/v1/auth${path}`,
      payload: payload as any,
    });
  const known = await post("/password/forgot", { email });
  const unknown = await post("/password/forgot", {
    email: "missing@example.test",
  });
  assert.equal(known.statusCode, 200);
  assert.equal(unknown.statusCode, 200);
  assert.deepEqual(known.json(), unknown.json());
  const registered = await pool.query(
    "SELECT id FROM users WHERE email_normalized='mailfail@example.test'",
  );
  await pool.query(
    "UPDATE email_verification_tokens SET created_at=now()-interval '1 minute' WHERE user_id=$1",
    [registered.rows[0].id],
  );
  const resendKnown = await post("/email/resend", {
    email: "mailfail@example.test",
  });
  const resendUnknown = await post("/email/resend", {
    email: "missing@example.test",
  });
  assert.equal(resendKnown.statusCode, 200);
  assert.deepEqual(resendKnown.json(), resendUnknown.json());
  const queue = await pool.query("SELECT * FROM email_outbox");
  assert.ok(queue.rowCount && queue.rowCount >= 2);
  assert.equal(
    queue.rows.some((row) => row.encrypted_payload.includes("example.test")),
    false,
  );
  assert.equal(
    await deliverQueued(pool, config, {
      send: async () => {
        throw new Error("SMTP unavailable");
      },
    }),
    false,
  );
  const retried = await pool.query("SELECT attempt_count FROM email_outbox");
  assert.ok(retried.rows.some((row) => row.attempt_count > 0));
  await pool.query("UPDATE email_outbox SET next_attempt_at=now()");
  const delivered: Mail[] = [];
  assert.equal(
    await deliverQueued(pool, config, {
      send: async (mail) => {
        delivered.push(mail);
      },
    }),
    true,
  );
  assert.equal(delivered.length, 1);
  await failing.close();
});

test("forgot and resend return after enqueueing without invoking or awaiting SMTP", async () => {
  let smtpCalls = 0;
  let releaseSmtp!: () => void;
  const deferred = new Promise<void>((resolve) => {
    releaseSmtp = resolve;
  });
  const queued = await buildApp(config, pool, {
    send: async () => {
      smtpCalls++;
      await deferred;
    },
  });
  const post = (path: string, payload: unknown) =>
    queued.inject({
      method: "POST",
      url: `/api/v1/auth${path}`,
      payload: payload as any,
    });
  let pending: Promise<unknown> | undefined;
  try {
    const registered = await pool.query(
      "SELECT id FROM users WHERE email_normalized='mailfail@example.test'",
    );
    await pool.query(
      "UPDATE email_verification_tokens SET created_at=now()-interval '1 minute' WHERE user_id=$1",
      [registered.rows[0].id],
    );
    const requests = [
      post("/password/forgot", { email }),
      post("/email/resend", { email: "mailfail@example.test" }),
    ];
    pending = Promise.all(requests);
    const responses = (await Promise.race([
      pending,
      new Promise<undefined>((resolve) =>
        setTimeout(() => resolve(undefined), 1000),
      ),
    ])) as Awaited<ReturnType<typeof post>>[] | undefined;
    assert.ok(
      responses,
      "Generic auth endpoints must not wait for SMTP completion.",
    );
    assert.equal(
      smtpCalls,
      0,
      "SMTP must run only through the background outbox worker.",
    );
    assert.ok(responses.every((response) => response.statusCode === 200));
    const outbox = await pool.query("SELECT kind FROM email_outbox");
    assert.ok(outbox.rows.some((row) => row.kind === "reset"));
    assert.ok(outbox.rows.some((row) => row.kind === "verification"));
  } finally {
    releaseSmtp();
    await pending;
    await queued.close();
  }
});
