import assert from "node:assert/strict";
import { test } from "node:test";
import sharp from "sharp";
import {
  AwsIdentityVerifier,
  createIdentityVerifier,
  type AwsIdentityOperations,
} from "../src/verification/aws-identity-verifier.js";

const image = await sharp({
  create: { width: 100, height: 100, channels: 3, background: "white" },
})
  .jpeg()
  .toBuffer();
const text = [
  "Full name: MAYA PATEL",
  "Date of birth: 16 JUL 1994",
  "Document number: AB123456",
];
function operations(
  overrides: Partial<AwsIdentityOperations> = {},
): AwsIdentityOperations {
  return {
    detectText: async () => ({
      Blocks: text.map((Text) => ({ BlockType: "LINE", Text, Confidence: 98 })),
      $metadata: {},
    }),
    detectFaces: async () => ({
      FaceDetails: [{ Confidence: 99 }],
      $metadata: {},
    }),
    compareFaces: async () => ({
      FaceMatches: [{ Similarity: 96.5 }],
      $metadata: {},
    }),
    ...overrides,
  };
}

test("real provider boundary extracts labeled OCR fields and applies configured face threshold", async () => {
  const result = await new AwsIdentityVerifier(operations(), 95, 7000).verify(
    image,
    image,
  );
  assert.equal(result.ocr.status, "succeeded");
  assert.equal(result.ocr.text, text.join("\n"));
  assert.deepEqual(result.ocr.fields, {
    fullName: "MAYA PATEL",
    dateOfBirth: "1994-07-16",
    documentNumber: "AB123456",
  });
  assert.equal(result.ocr.confidence, 98);
  assert.deepEqual(result.faceMatch, {
    status: "matched",
    similarity: 96.5,
    threshold: 95,
  });
});

test("empty document and a low score never manufacture successful evidence", async () => {
  const result = await new AwsIdentityVerifier(
    operations({
      detectText: async () => ({ Blocks: [], $metadata: {} }),
      compareFaces: async () => ({
        FaceMatches: [{ Similarity: 42 }],
        $metadata: {},
      }),
    }),
    90,
    7000,
  ).verify(image, image);
  assert.equal(result.ocr.status, "no_text");
  assert.deepEqual(result.ocr.fields, {
    fullName: null,
    dateOfBirth: null,
    documentNumber: null,
  });
  assert.equal(result.faceMatch.status, "not_matched");
  assert.equal(result.faceMatch.similarity, 42);
});

test("missing or multiple faces skip comparison", async () => {
  for (const count of [0, 2]) {
    let comparisons = 0;
    const result = await new AwsIdentityVerifier(
      operations({
        detectFaces: async () => ({
          FaceDetails: Array.from({ length: count }, () => ({
            Confidence: 99,
          })),
          $metadata: {},
        }),
        compareFaces: async () => {
          comparisons++;
          throw new Error("should not compare");
        },
      }),
      90,
      7000,
    ).verify(image, image);
    assert.equal(
      result.faceMatch.status,
      count === 0 ? "no_face" : "multiple_faces",
    );
    assert.equal(result.faceMatch.similarity, null);
    assert.equal(comparisons, 0);
  }
});

test("single-sided face ambiguity cannot be hidden by the largest face behavior", async () => {
  let calls = 0;
  let comparisons = 0;
  const result = await new AwsIdentityVerifier(
    operations({
      detectFaces: async () => ({
        FaceDetails: Array.from({ length: ++calls === 1 ? 1 : 2 }, () => ({
          Confidence: 99,
        })),
        $metadata: {},
      }),
      compareFaces: async () => {
        comparisons++;
        return { FaceMatches: [{ Similarity: 99 }], $metadata: {} };
      },
    }),
    90,
    7000,
  ).verify(image, image);
  assert.equal(result.faceMatch.status, "multiple_faces");
  assert.equal(comparisons, 0);
});

test("one provider failure retains the other check and never exposes exception text", async () => {
  const result = await new AwsIdentityVerifier(
    operations({
      detectText: async () => {
        throw new Error("secret provider response and PII");
      },
    }),
    90,
    7000,
  ).verify(image, image);
  assert.equal(result.ocr.status, "failed");
  assert.equal(result.faceMatch.status, "matched");
  assert.ok(!JSON.stringify(result).includes("secret"));
});

test("global timeout aborts stalled work while preserving completed OCR", async () => {
  let signal: AbortSignal | undefined;
  const result = await new AwsIdentityVerifier(
    operations({
      detectFaces: async (_bytes, abortSignal) => {
        signal = abortSignal;
        return new Promise(() => {});
      },
    }),
    90,
    500,
  ).verify(image, image);
  assert.equal(result.ocr.status, "succeeded");
  assert.equal(result.faceMatch.status, "failed");
  assert.equal(signal?.aborted, true);
});

test("unlabeled and ambiguous dates are left for human review", async () => {
  const result = await new AwsIdentityVerifier(
    operations({
      detectText: async () => ({
        Blocks: [
          "UNLABELED NAME",
          "Date of birth: 04/05/1994",
          "Document number: ???",
        ].map((Text) => ({ BlockType: "LINE", Text, Confidence: 95 })),
        $metadata: {},
      }),
    }),
    90,
    7000,
  ).verify(image, image);
  assert.deepEqual(result.ocr.fields, {
    fullName: null,
    dateOfBirth: null,
    documentNumber: null,
  });
});

test("split labels and surname/given names are supported without overwriting user details", async () => {
  const result = await new AwsIdentityVerifier(
    operations({
      detectText: async () => ({
        Blocks: [
          "Surname",
          "PATEL",
          "Given names",
          "MAYA",
          "DOB",
          "1994-07-16",
          "Passport no.",
          "AB123456",
        ].map((Text) => ({ BlockType: "LINE", Text, Confidence: 95 })),
        $metadata: {},
      }),
    }),
    90,
    7000,
  ).verify(image, image);
  assert.deepEqual(result.ocr.fields, {
    fullName: "MAYA PATEL",
    dateOfBirth: "1994-07-16",
    documentNumber: "AB123456",
  });
});

test("malformed similarity and incomplete AWS output are failures, never matches", async () => {
  const result = await new AwsIdentityVerifier(
    operations({
      compareFaces: async () => ({
        FaceMatches: [{ Similarity: Number.NaN }],
        $metadata: {},
      }),
    }),
    90,
    7000,
  ).verify(image, image);
  assert.equal(result.faceMatch.status, "failed");
  assert.equal(result.faceMatch.similarity, null);
});

test("provider is disabled unless explicitly configured", () => {
  assert.equal(createIdentityVerifier({} as never), null);
});

test("incomplete OCR response is a failed check rather than proof of no text", async () => {
  const result = await new AwsIdentityVerifier(
    operations({ detectText: async () => ({ $metadata: {} }) }),
    90,
    7000,
  ).verify(image, image);
  assert.equal(result.ocr.status, "failed");
  assert.equal(result.faceMatch.status, "matched");
});

test("parent and issuer name labels never become applicant name suggestions", async () => {
  const result = await new AwsIdentityVerifier(
    operations({
      detectText: async () => ({
        Blocks: [
          "Name of father: SYNTHETIC PARENT",
          "Name of mother: SYNTHETIC MOTHER",
          "Full name of issuer: SYNTHETIC AUTHORITY",
          "Surname of father: PARENT",
          "Given names of father: GUARDIAN",
        ].map((Text) => ({ BlockType: "LINE", Text, Confidence: 99 })),
        $metadata: {},
      }),
    }),
    90,
    7000,
  ).verify(image, image);
  assert.equal(result.ocr.status, "succeeded");
  assert.equal(result.ocr.fields.fullName, null);
});

test("an empty name label followed by another labeled field cannot consume that field", async () => {
  const result = await new AwsIdentityVerifier(
    operations({
      detectText: async () => ({
        Blocks: [
          "Name",
          "Name of father: SYNTHETIC PARENT",
          "Full name: SYNTHETIC APPLICANT",
        ].map((Text) => ({ BlockType: "LINE", Text, Confidence: 99 })),
        $metadata: {},
      }),
    }),
    90,
    7000,
  ).verify(image, image);
  assert.equal(result.ocr.fields.fullName, "SYNTHETIC APPLICANT");
});
