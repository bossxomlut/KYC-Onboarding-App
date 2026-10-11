import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { test } from "node:test";
import { loadConfig } from "../src/config.js";

test("verification is opt-in and requires bounded, explicit backend configuration", () => {
  const previous = { ...process.env };
  try {
    process.env.NODE_ENV = "test";
    process.env.DATABASE_URL = "postgresql://unused";
    for (const name of ["JWT_SECRET", "TOKEN_PEPPER", "MEDIA_ENCRYPTION_KEY"])
      process.env[name] = randomBytes(32).toString("base64");
    for (const name of [
      "KYC_VERIFICATION_PROVIDER",
      "AWS_REGION",
      "KYC_FACE_MATCH_THRESHOLD",
      "KYC_VERIFICATION_TIMEOUT_MS",
    ])
      delete process.env[name];
    assert.equal(loadConfig().verification, undefined);
    process.env.KYC_VERIFICATION_PROVIDER = "aws";
    assert.throws(() => loadConfig(), /AWS_REGION is required/);
    process.env.AWS_REGION = "ap-southeast-1";
    assert.deepEqual(loadConfig().verification, {
      provider: "aws",
      region: "ap-southeast-1",
      faceMatchThreshold: 90,
      timeoutMs: 7000,
    });
    for (const value of ["0", "101", "NaN"]) {
      process.env.KYC_FACE_MATCH_THRESHOLD = value;
      assert.throws(() => loadConfig());
    }
    process.env.KYC_FACE_MATCH_THRESHOLD = "95";
    for (const value of ["999", "8001", "NaN"]) {
      process.env.KYC_VERIFICATION_TIMEOUT_MS = value;
      assert.throws(() => loadConfig());
    }
    process.env.KYC_VERIFICATION_TIMEOUT_MS = "5000";
    assert.equal(loadConfig().verification?.timeoutMs, 5000);
    process.env.KYC_VERIFICATION_PROVIDER = "unknown";
    assert.throws(() => loadConfig());
  } finally {
    for (const name of Object.keys(process.env))
      if (!(name in previous)) delete process.env[name];
    Object.assign(process.env, previous);
  }
});
