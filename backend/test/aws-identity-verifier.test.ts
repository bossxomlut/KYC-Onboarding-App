import assert from "node:assert/strict";
import { test } from "node:test";
import sharp from "sharp";
import type { DetectFacesCommandOutput } from "@aws-sdk/client-rekognition";
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
const selfieImage = await sharp({
  create: { width: 120, height: 100, channels: 3, background: "blue" },
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

const faces = (count: number): DetectFacesCommandOutput => ({
  FaceDetails: Array.from({ length: count }, () => ({ Confidence: 99 })),
  $metadata: {},
});

type Detection = (signal: AbortSignal) => Promise<DetectFacesCommandOutput>;
function independentOperations(
  documentFaces: Detection,
  selfieFaces: Detection,
  overrides: Partial<AwsIdentityOperations> = {},
): AwsIdentityOperations {
  return operations({
    detectFaces: async (bytes, signal) =>
      (await sharp(bytes).metadata()).width === 120
        ? selfieFaces(signal)
        : documentFaces(signal),
    ...overrides,
  });
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
  assert.deepEqual(result.selfieFace, { status: "detected" });
  assert.deepEqual(result.faceMatch, {
    status: "matched",
    similarity: 96.5,
    threshold: 95,
  });
});

test("a detected selfie face is retained when the document has no face", async () => {
  let detections = 0;
  let comparisons = 0;
  const result = await new AwsIdentityVerifier(
    independentOperations(
      async () => {
        detections++;
        return faces(0);
      },
      async () => {
        detections++;
        return faces(1);
      },
      {
        compareFaces: async () => {
          comparisons++;
          throw new Error("should not compare");
        },
      },
    ),
    90,
    7000,
  ).verify(image, selfieImage);
  assert.deepEqual(result.selfieFace, { status: "detected" });
  assert.equal(result.faceMatch.status, "no_face");
  assert.equal(result.ocr.status, "succeeded");
  assert.equal(detections, 2);
  assert.equal(comparisons, 0);
});

for (const count of [0, 2]) {
  test(`selfie with ${count} faces is a separate failed prerequisite for comparison`, async () => {
    let comparisons = 0;
    const result = await new AwsIdentityVerifier(
      independentOperations(
        async () => faces(count === 0 ? 2 : 0),
        async () => faces(count),
        {
          compareFaces: async () => {
            comparisons++;
            throw new Error("should not compare");
          },
        },
      ),
      90,
      7000,
    ).verify(image, selfieImage);
    const status = count === 0 ? "no_face" : "multiple_faces";
    assert.deepEqual(result.selfieFace, { status });
    assert.equal(result.faceMatch.status, status);
    assert.equal(result.faceMatch.similarity, null);
    assert.equal(result.ocr.status, "succeeded");
    assert.equal(comparisons, 0);
  });
}

for (const failure of ["reject", "stall"] as const) {
  test(`document detection ${failure} preserves a completed selfie check and OCR`, async () => {
    let comparisons = 0;
    let documentSignal: AbortSignal | undefined;
    const result = await new AwsIdentityVerifier(
      independentOperations(
        async (signal) => {
          documentSignal = signal;
          if (failure === "reject") throw new Error("private document error");
          return new Promise(() => {});
        },
        async () => faces(1),
        {
          compareFaces: async () => {
            comparisons++;
            throw new Error("should not compare");
          },
        },
      ),
      90,
      500,
    ).verify(image, selfieImage);
    assert.deepEqual(result.selfieFace, { status: "detected" });
    assert.equal(result.faceMatch.status, "failed");
    assert.equal(result.ocr.status, "succeeded");
    assert.equal(comparisons, 0);
    assert.equal(documentSignal?.aborted, true);
    assert.ok(!JSON.stringify(result).includes("private"));
  });

  test(`face comparison ${failure} preserves completed selfie detection and OCR`, async () => {
    let detections = 0;
    let comparisonSignal: AbortSignal | undefined;
    const detect: Detection = async () => {
      detections++;
      return faces(1);
    };
    const result = await new AwsIdentityVerifier(
      independentOperations(detect, detect, {
        compareFaces: async (_document, _selfie, signal) => {
          comparisonSignal = signal;
          if (failure === "reject") throw new Error("private comparison error");
          return new Promise(() => {});
        },
      }),
      90,
      500,
    ).verify(image, selfieImage);
    assert.deepEqual(result.selfieFace, { status: "detected" });
    assert.equal(result.faceMatch.status, "failed");
    assert.equal(result.ocr.status, "succeeded");
    assert.equal(detections, 2);
    assert.equal(comparisonSignal?.aborted, true);
    assert.ok(!JSON.stringify(result).includes("private"));
  });
}

test("invalid document encoding does not suppress a valid selfie face check", async () => {
  let detections = 0;
  const result = await new AwsIdentityVerifier(
    operations({
      detectFaces: async () => {
        detections++;
        return faces(1);
      },
    }),
    90,
    7000,
  ).verify(Buffer.from("invalid document bytes"), selfieImage);
  assert.deepEqual(result.selfieFace, { status: "detected" });
  assert.equal(result.ocr.status, "failed");
  assert.equal(result.faceMatch.status, "failed");
  assert.equal(detections, 1);
});

test("invalid selfie encoding does not suppress independently completed OCR", async () => {
  let comparisons = 0;
  const result = await new AwsIdentityVerifier(
    operations({
      compareFaces: async () => {
        comparisons++;
        throw new Error("should not compare");
      },
    }),
    90,
    7000,
  ).verify(image, Buffer.from("invalid selfie bytes"));
  assert.deepEqual(result.selfieFace, { status: "failed" });
  assert.equal(result.ocr.status, "succeeded");
  assert.equal(result.faceMatch.status, "failed");
  assert.equal(comparisons, 0);
});

test("incomplete selfie detection is a failure even if document ambiguity is known", async () => {
  const result = await new AwsIdentityVerifier(
    independentOperations(
      async () => faces(2),
      async () => ({ $metadata: {} }),
    ),
    90,
    7000,
  ).verify(image, selfieImage);
  assert.deepEqual(result.selfieFace, { status: "failed" });
  assert.equal(result.faceMatch.status, "failed");
  assert.equal(result.ocr.status, "succeeded");
});

test("selfie face absence remains known even if document detection stalls", async () => {
  const result = await new AwsIdentityVerifier(
    independentOperations(
      async () => new Promise(() => {}),
      async () => faces(0),
    ),
    90,
    500,
  ).verify(image, selfieImage);
  assert.deepEqual(result.selfieFace, { status: "no_face" });
  assert.equal(result.faceMatch.status, "no_face");
  assert.equal(result.ocr.status, "succeeded");
});

test("provider completion after global timeout cannot update returned evidence or launch comparison", async () => {
  let finishSelfie: ((value: DetectFacesCommandOutput) => void) | undefined;
  let comparisons = 0;
  const result = await new AwsIdentityVerifier(
    independentOperations(
      async () => faces(1),
      async () =>
        new Promise((resolve) => {
          finishSelfie = resolve;
        }),
      {
        compareFaces: async () => {
          comparisons++;
          return { FaceMatches: [{ Similarity: 99 }], $metadata: {} };
        },
      },
    ),
    90,
    500,
  ).verify(image, selfieImage);
  const returned = structuredClone(result);
  assert.deepEqual(result.selfieFace, { status: "failed" });
  assert.equal(result.ocr.status, "succeeded");
  assert.ok(finishSelfie);
  finishSelfie(faces(1));
  await new Promise((resolve) => setImmediate(resolve));
  assert.deepEqual(result, returned);
  assert.equal(comparisons, 0);
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
