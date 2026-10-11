import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { PassThrough } from "node:stream";
import { test } from "node:test";
import type { ChildProcessWithoutNullStreams } from "node:child_process";
import {
  LocalIdentityVerifier,
  type LocalIdentitySpawner,
} from "../src/verification/local-identity-verifier.js";

const valid = () => ({
  ocr: {
    status: "succeeded",
    text: "Họ và tên: NGUYỄN VĂN TEST\nSố: 012345678901",
    fields: {
      fullName: "NGUYỄN VĂN TEST",
      dateOfBirth: "1990-01-01",
      documentNumber: "012345678901",
    },
    confidence: 92,
  },
  selfieFace: { status: "detected" },
  faceMatch: { status: "matched", similarity: 86, threshold: 36.3 },
});

function boundary(run: (child: ReturnType<typeof childProcess>) => void) {
  const child = childProcess();
  let command: string | undefined;
  let args: readonly string[] | undefined;
  let options: Parameters<LocalIdentitySpawner>[2] | undefined;
  const spawn: LocalIdentitySpawner = (
    givenCommand,
    givenArgs,
    givenOptions,
  ) => {
    command = givenCommand;
    args = givenArgs;
    options = givenOptions;
    child.stdin.on("finish", () => run(child));
    return child as unknown as ChildProcessWithoutNullStreams;
  };
  const verifier = new LocalIdentityVerifier(
    "/test/python",
    "/test/models",
    36.3,
    100,
    spawn,
  );
  return { child, verifier, configuration: () => ({ command, args, options }) };
}

function childProcess() {
  const child = Object.assign(new EventEmitter(), {
    stdin: new PassThrough(),
    stdout: new PassThrough(),
    stderr: new PassThrough(),
    killed: false,
    kill: () => {
      child.killed = true;
      return true;
    },
  });
  return child;
}

test("local process receives private images over stdin and returns Vietnamese OCR with face comparison", async () => {
  let input = "";
  const adapter = boundary((child) => {
    child.stdout.end(JSON.stringify(valid()));
    child.emit("close", 0);
  });
  adapter.child.stdin.on("data", (part) => {
    input += part.toString();
  });
  const result = await adapter.verifier.verify(
    Buffer.from("document"),
    Buffer.from("selfie"),
  );
  assert.deepEqual(result, valid());
  assert.deepEqual(JSON.parse(input), {
    document: Buffer.from("document").toString("base64"),
    selfie: Buffer.from("selfie").toString("base64"),
    threshold: 36.3,
  });
  const { command, args, options } = adapter.configuration();
  assert.equal(command, "/test/python");
  assert.equal(args?.length, 1);
  assert.match(args![0]!, /\/backend\/local-verification\/engine.py$/);
  assert.equal(options?.env?.KYC_LOCAL_MODELS_DIR, "/test/models");
  assert.equal(options?.env?.TESSDATA_PREFIX, "/test/models/tessdata");
  assert.equal(options?.env?.KYC_LOCAL_OCR_LANGUAGES, "vie");
  assert.equal(options?.detached, process.platform !== "win32");
});

test("local OCR language is fixed by adapter configuration rather than later environment changes", async () => {
  let language: string | undefined;
  const child = childProcess();
  const launch: LocalIdentitySpawner = (_command, _args, options) => {
    language = options.env?.KYC_LOCAL_OCR_LANGUAGES;
    child.stdin.on("finish", () => {
      child.stdout.end(JSON.stringify(valid()));
      child.emit("close", 0);
    });
    return child as unknown as ChildProcessWithoutNullStreams;
  };
  const adapter = new LocalIdentityVerifier(
    "/test/python",
    "/test/models",
    36.3,
    100,
    launch,
    "eng",
  );
  const previous = process.env.KYC_LOCAL_OCR_LANGUAGES;
  try {
    process.env.KYC_LOCAL_OCR_LANGUAGES = "vie";
    assert.equal(
      (await adapter.verify(Buffer.from("image"), Buffer.from("image"))).ocr
        .status,
      "succeeded",
    );
    assert.equal(language, "eng");
  } finally {
    if (previous === undefined) delete process.env.KYC_LOCAL_OCR_LANGUAGES;
    else process.env.KYC_LOCAL_OCR_LANGUAGES = previous;
  }
});

test("timeout terminates local processing without exposing stderr or private inputs", async () => {
  const adapter = boundary((child) => {
    child.stderr.write("secret document and credential detail");
  });
  const result = await adapter.verifier.verify(
    Buffer.from("private"),
    Buffer.from("private"),
  );
  assert.equal(adapter.child.killed, true);
  assert.equal(result.ocr.status, "failed");
  assert.equal(result.selfieFace.status, "failed");
  assert.equal(result.faceMatch.status, "failed");
  assert.equal(JSON.stringify(result).includes("secret"), false);
});

test("oversized or malformed engine output is rejected and terminated", async () => {
  for (const response of [
    "x".repeat(128 * 1024 + 1),
    "not json",
    JSON.stringify({
      ...valid(),
      faceMatch: { status: "matched", similarity: 101, threshold: 36.3 },
    }),
    JSON.stringify({
      ...valid(),
      ocr: { ...valid().ocr, text: "x".repeat(20001) },
    }),
    JSON.stringify({ ...valid(), extra: "secret" }),
  ]) {
    const adapter = boundary((child) => {
      child.stdout.end(response);
      child.emit("close", 0);
    });
    const result = await adapter.verifier.verify(
      Buffer.from("image"),
      Buffer.from("image"),
    );
    assert.equal(result.ocr.status, "failed");
    assert.equal(result.faceMatch.status, "failed");
  }
});

test("nonzero exit and launch errors fail closed", async () => {
  for (const mode of ["exit", "error", "stderr"]) {
    const adapter = boundary((child) => {
      child.stdout.end(JSON.stringify(valid()));
      if (mode === "exit") child.emit("close", 1);
      else if (mode === "stderr")
        child.stderr.emit("error", new Error("private stream details"));
      else child.emit("error", new Error("private engine configuration"));
    });
    const result = await adapter.verifier.verify(
      Buffer.from("image"),
      Buffer.from("image"),
    );
    assert.equal(result.faceMatch.status, "failed");
  }
});

test("local comparison status and score must agree with the configured threshold", async () => {
  const adapter = boundary((child) => {
    child.stdout.end(
      JSON.stringify({
        ...valid(),
        faceMatch: { status: "matched", similarity: 12, threshold: 36.3 },
      }),
    );
    child.emit("close", 0);
  });
  const result = await adapter.verifier.verify(
    Buffer.from("image"),
    Buffer.from("image"),
  );
  assert.equal(result.faceMatch.status, "failed");
});

test("no-text and missing-face outcomes remain semantic results, and partial OCR success survives a face failure", async () => {
  const noText = {
    status: "no_text",
    text: "",
    fields: { fullName: null, dateOfBirth: null, documentNumber: null },
    confidence: null,
  };
  for (const expected of [
    {
      ocr: noText,
      selfieFace: { status: "no_face" },
      faceMatch: { status: "no_face", similarity: null, threshold: 36.3 },
    },
    {
      ...valid(),
      faceMatch: { status: "failed", similarity: null, threshold: 36.3 },
    },
  ]) {
    const adapter = boundary((child) => {
      child.stdout.end(JSON.stringify(expected));
      child.emit("close", 0);
    });
    assert.deepEqual(
      await adapter.verifier.verify(Buffer.from("image"), Buffer.from("image")),
      expected,
    );
  }
});

test("selfie presence is separate from comparison and must agree with comparison prerequisites", async () => {
  for (const [selfieStatus, comparisonStatus] of [
    ["detected", "no_face"], // A valid selfie with no face in the document.
    ["detected", "failed"], // Comparison failure does not erase detection.
    ["no_face", "no_face"],
    ["multiple_faces", "multiple_faces"],
    ["failed", "failed"],
  ]) {
    const expected = {
      ...valid(),
      selfieFace: { status: selfieStatus },
      faceMatch: {
        status: comparisonStatus,
        similarity: null,
        threshold: 36.3,
      },
    };
    const adapter = boundary((child) => {
      child.stdout.end(JSON.stringify(expected));
      child.emit("close", 0);
    });
    assert.deepEqual(
      await adapter.verifier.verify(Buffer.from("image"), Buffer.from("image")),
      expected,
    );
  }
});

test("missing or contradictory selfie evidence is never accepted as a face match", async () => {
  const { selfieFace: _legacy, ...legacy } = valid();
  for (const response of [
    legacy,
    { ...valid(), selfieFace: { status: "unknown" } },
    { ...valid(), selfieFace: { status: "no_face" } },
    { ...valid(), selfieFace: { status: "multiple_faces" } },
    { ...valid(), selfieFace: { status: "failed" } },
  ]) {
    const adapter = boundary((child) => {
      child.stdout.end(JSON.stringify(response));
      child.emit("close", 0);
    });
    const result = await adapter.verifier.verify(
      Buffer.from("image"),
      Buffer.from("image"),
    );
    assert.equal(result.selfieFace.status, "failed");
    assert.equal(result.faceMatch.status, "failed");
  }
});

test("oversized inputs never start a subprocess", async () => {
  const adapter = boundary(() => {
    assert.fail("subprocess should not run");
  });
  const result = await adapter.verifier.verify(
    Buffer.alloc(20 * 1024 * 1024),
    Buffer.from("image"),
  );
  assert.equal(adapter.configuration().command, undefined);
  assert.equal(result.ocr.status, "failed");
});
