import {
  TextractClient,
  DetectDocumentTextCommand,
  type DetectDocumentTextCommandOutput,
} from "@aws-sdk/client-textract";
import {
  RekognitionClient,
  DetectFacesCommand,
  CompareFacesCommand,
  type DetectFacesCommandOutput,
  type CompareFacesCommandOutput,
} from "@aws-sdk/client-rekognition";
import sharp from "sharp";
import type { Config } from "../config.js";
import type {
  FaceMatchResult,
  IdentityCheckResult,
  IdentityVerifier,
  OcrResult,
} from "./identity-verifier.js";

/** SDK operations are the only test double boundary; no mock provider is used
 * by the running API. Both detection and comparison use image bytes, no S3. */
export interface AwsIdentityOperations {
  detectText(
    document: Buffer,
    signal: AbortSignal,
  ): Promise<DetectDocumentTextCommandOutput>;
  detectFaces(
    image: Buffer,
    signal: AbortSignal,
  ): Promise<DetectFacesCommandOutput>;
  compareFaces(
    document: Buffer,
    selfie: Buffer,
    signal: AbortSignal,
  ): Promise<CompareFacesCommandOutput>;
}

const emptyFields = () => ({
  fullName: null,
  dateOfBirth: null,
  documentNumber: null,
});
const failedOcr = (): OcrResult => ({
  status: "failed",
  text: "",
  fields: emptyFields(),
  confidence: null,
});

const labels = {
  // A name label is exact (split line) or colon-delimited. Parent/issuer labels
  // such as "Name of father" must not be treated as the applicant's name.
  fullName: /^(?:full\s*name|name)(?:\s*:\s*|\s*$)(.*)$/i,
  surname: /^(?:surname|last\s*name)(?:\s*:\s*|\s*$)(.*)$/i,
  givenNames: /^(?:given\s*names?|first\s*names?)(?:\s*:\s*|\s*$)(.*)$/i,
  dateOfBirth: /^(?:date\s*of\s*birth|birth\s*date|dob)\b\s*[:.-]?\s*(.*)$/i,
  documentNumber:
    /^(?:(?:document|passport|id|identity|licen[cs]e)\s*(?:number|no\.?|#))\s*[:.-]?\s*(.*)$/i,
};

function labeledValue(lines: string[], label: RegExp): string | null {
  for (let index = 0; index < lines.length; index++) {
    const match = label.exec(lines[index]!);
    if (!match) continue;
    const candidate = match[1]?.trim() || lines[index + 1]?.trim();
    if (
      candidate &&
      !candidate.includes(":") &&
      !Object.values(labels).some((pattern) => pattern.test(candidate))
    )
      return candidate;
  }
  return null;
}

function birthDate(value: string | null): string | null {
  if (!value) return null;
  const iso = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  const named = /^(\d{1,2})\s+([A-Za-z]{3,9})\s+(\d{4})$/.exec(value);
  let result: string;
  if (iso) result = value;
  else if (named) {
    const month = [
      "jan",
      "feb",
      "mar",
      "apr",
      "may",
      "jun",
      "jul",
      "aug",
      "sep",
      "oct",
      "nov",
      "dec",
    ].indexOf(named[2]!.slice(0, 3).toLowerCase());
    if (month < 0) return null;
    result = `${named[3]}-${String(month + 1).padStart(2, "0")}-${named[1]!.padStart(2, "0")}`;
  } else return null; // Ambiguous numeric dates require the applicant's review.
  const date = new Date(`${result}T00:00:00Z`);
  if (
    !Number.isFinite(date.getTime()) ||
    date.toISOString().slice(0, 10) !== result ||
    Number(result.slice(0, 4)) < 1900
  )
    return null;
  return result;
}

function parsedOcr(response: DetectDocumentTextCommandOutput): OcrResult {
  if (!response.Blocks) throw new Error("Incomplete OCR response.");
  const blocks = (response.Blocks ?? []).filter(
    (block) => block.BlockType === "LINE" && block.Text?.trim(),
  );
  // Bound persisted PII and protect the existing mobile response budget.
  const lines = blocks
    .slice(0, 200)
    .map((block) => block.Text!.trim().slice(0, 500));
  if (!lines.length)
    return {
      status: "no_text",
      text: "",
      fields: emptyFields(),
      confidence: null,
    };
  const directName = labeledValue(lines, labels.fullName);
  const surname = labeledValue(lines, labels.surname);
  const givenNames = labeledValue(lines, labels.givenNames);
  const fullName =
    directName ?? (surname && givenNames ? `${givenNames} ${surname}` : null);
  const documentNumber = labeledValue(lines, labels.documentNumber);
  const scores = blocks
    .slice(0, 200)
    .map((block) => block.Confidence)
    .filter(
      (value): value is number =>
        typeof value === "number" &&
        Number.isFinite(value) &&
        value >= 0 &&
        value <= 100,
    );
  return {
    status: "succeeded",
    text: lines.join("\n").slice(0, 20_000),
    fields: {
      fullName:
        fullName &&
        fullName.length >= 2 &&
        fullName.length <= 120 &&
        /\p{L}/u.test(fullName)
          ? fullName
          : null,
      dateOfBirth: birthDate(labeledValue(lines, labels.dateOfBirth)),
      documentNumber:
        documentNumber && /^[A-Za-z0-9 -]{4,40}$/.test(documentNumber)
          ? documentNumber
          : null,
    },
    confidence: scores.length
      ? Math.round(
          (scores.reduce((sum, score) => sum + score, 0) / scores.length) * 100,
        ) / 100
      : null,
  };
}

async function prepare(image: Buffer): Promise<Buffer> {
  // Rekognition limits image bytes to 5MB. Keep portrait/document aspect ratio;
  // AWS receives a fresh metadata-free JPEG, never the original EXIF/GPS.
  let bytes = await sharp(image)
    .resize({
      width: 4096,
      height: 4096,
      fit: "inside",
      withoutEnlargement: true,
    })
    .jpeg({ quality: 90 })
    .toBuffer();
  if (bytes.length > 5 * 1024 * 1024)
    bytes = await sharp(bytes)
      .resize({
        width: 2048,
        height: 2048,
        fit: "inside",
        withoutEnlargement: true,
      })
      .jpeg({ quality: 80 })
      .toBuffer();
  if (bytes.length > 5 * 1024 * 1024)
    throw new Error("Image exceeds provider limit.");
  return bytes;
}

export class AwsIdentityVerifier implements IdentityVerifier {
  constructor(
    private readonly operations: AwsIdentityOperations,
    private readonly threshold: number,
    private readonly timeoutMs: number,
  ) {}

  async verify(document: Buffer, selfie: Buffer): Promise<IdentityCheckResult> {
    const controller = new AbortController();
    let ocr = failedOcr();
    let faceMatch: FaceMatchResult = {
      status: "failed",
      similarity: null,
      threshold: this.threshold,
    };
    let timer: ReturnType<typeof setTimeout> | undefined;
    const timeout = new Promise<void>((resolve) => {
      timer = setTimeout(() => {
        controller.abort();
        resolve();
      }, this.timeoutMs);
    });
    const work = async () => {
      const [documentBytes, selfieBytes] = await Promise.all([
        prepare(document),
        prepare(selfie),
      ]);
      if (controller.signal.aborted) return;
      await Promise.all([
        this.operations
          .detectText(documentBytes, controller.signal)
          .then((response) => {
            ocr = parsedOcr(response);
          })
          .catch(() => {}),
        this.compare(documentBytes, selfieBytes, controller.signal)
          .then((result) => {
            faceMatch = result;
          })
          .catch(() => {}),
      ]);
    };
    try {
      // Covers encoding, credentials lookup and every SDK operation together.
      // Even an SDK/credential source which ignores abort cannot stall HTTP.
      await Promise.race([work().catch(() => {}), timeout]);
      return { ocr, faceMatch };
    } finally {
      if (timer) clearTimeout(timer);
      controller.abort();
    }
  }

  private async compare(
    document: Buffer,
    selfie: Buffer,
    signal: AbortSignal,
  ): Promise<FaceMatchResult> {
    const [source, target] = await Promise.all([
      this.operations.detectFaces(document, signal),
      this.operations.detectFaces(selfie, signal),
    ]);
    if (!source.FaceDetails || !target.FaceDetails)
      throw new Error("Incomplete face detection response.");
    const count = [source.FaceDetails.length, target.FaceDetails.length];
    if (count.some((value) => value > 1))
      return {
        status: "multiple_faces",
        similarity: null,
        threshold: this.threshold,
      };
    if (count.some((value) => value === 0))
      return { status: "no_face", similarity: null, threshold: this.threshold };
    if (signal.aborted) throw new Error("Timed out.");
    const result = await this.operations.compareFaces(document, selfie, signal);
    if (!result.FaceMatches)
      throw new Error("Incomplete face comparison response.");
    const similarity = result.FaceMatches[0]?.Similarity;
    if (similarity === undefined && result.FaceMatches.length === 0)
      return {
        status: "not_matched",
        similarity: null,
        threshold: this.threshold,
      };
    if (
      typeof similarity !== "number" ||
      !Number.isFinite(similarity) ||
      similarity < 0 ||
      similarity > 100
    )
      throw new Error("Invalid similarity score.");
    return {
      status: similarity >= this.threshold ? "matched" : "not_matched",
      similarity,
      threshold: this.threshold,
    };
  }
}

export function createIdentityVerifier(
  config: Config,
): IdentityVerifier | null {
  if (!config.verification || config.verification.provider !== "aws")
    return null;
  const { region, faceMatchThreshold, timeoutMs } = config.verification;
  const clientConfig = { region, maxAttempts: 1 };
  // Standard SDK credential chain: IAM role or local AWS profile/env. Never
  // pass credentials to Flutter or log SDK errors/responses containing PII.
  const textract = new TextractClient(clientConfig);
  const rekognition = new RekognitionClient(clientConfig);
  return new AwsIdentityVerifier(
    {
      detectText: (bytes, signal) =>
        textract.send(
          new DetectDocumentTextCommand({ Document: { Bytes: bytes } }),
          { abortSignal: signal },
        ),
      detectFaces: (bytes, signal) =>
        rekognition.send(
          new DetectFacesCommand({
            Image: { Bytes: bytes },
            Attributes: ["DEFAULT"],
          }),
          { abortSignal: signal },
        ),
      compareFaces: (document, selfie, signal) =>
        rekognition.send(
          new CompareFacesCommand({
            SourceImage: { Bytes: document },
            TargetImage: { Bytes: selfie },
            SimilarityThreshold: 0,
            QualityFilter: "NONE",
          }),
          { abortSignal: signal },
        ),
    },
    faceMatchThreshold,
    timeoutMs,
  );
}
