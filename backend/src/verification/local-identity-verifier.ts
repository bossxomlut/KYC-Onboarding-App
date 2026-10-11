import {
  spawn,
  type ChildProcessWithoutNullStreams,
  type SpawnOptionsWithoutStdio,
} from "node:child_process";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { z } from "zod";
import type { LocalOcrLanguages } from "../config.js";
import type {
  IdentityCheckResult,
  IdentityVerifier,
} from "./identity-verifier.js";

export type LocalIdentitySpawner = (
  command: string,
  args: readonly string[],
  options: SpawnOptionsWithoutStdio,
) => ChildProcessWithoutNullStreams;

const score = z.number().finite().min(0).max(100);
const resultSchema = z
  .object({
    ocr: z
      .object({
        status: z.enum(["succeeded", "no_text", "failed"]),
        text: z.string().max(20_000),
        fields: z
          .object({
            fullName: z.string().min(2).max(120).nullable(),
            dateOfBirth: z.iso.date().nullable(),
            documentNumber: z.string().min(4).max(40).nullable(),
          })
          .strict(),
        confidence: score.nullable(),
      })
      .strict(),
    selfieFace: z
      .object({
        status: z.enum(["detected", "no_face", "multiple_faces", "failed"]),
      })
      .strict(),
    faceMatch: z
      .object({
        status: z.enum([
          "matched",
          "not_matched",
          "no_face",
          "multiple_faces",
          "failed",
        ]),
        similarity: score.nullable(),
        threshold: score.min(1),
      })
      .strict(),
  })
  .strict();

const maxOutputBytes = 128 * 1024;
const maxInputBytes = 20 * 1024 * 1024;
const enginePath = fileURLToPath(
  new URL("../../local-verification/engine.py", import.meta.url),
);

/** Real local OCR and face comparison: binary image payloads stay on stdin,
 * never shell arguments, files, logs or external network requests. */
export class LocalIdentityVerifier implements IdentityVerifier {
  constructor(
    private readonly pythonPath: string,
    private readonly modelsDir: string,
    private readonly threshold: number,
    private readonly timeoutMs: number,
    private readonly launch: LocalIdentitySpawner = (command, args, options) =>
      spawn(command, args, { ...options, stdio: "pipe" }),
    private readonly ocrLanguages: LocalOcrLanguages = "vie",
  ) {}

  async verify(document: Buffer, selfie: Buffer): Promise<IdentityCheckResult> {
    const failed = (): IdentityCheckResult => ({
      ocr: {
        status: "failed",
        text: "",
        fields: { fullName: null, dateOfBirth: null, documentNumber: null },
        confidence: null,
      },
      selfieFace: { status: "failed" },
      faceMatch: {
        status: "failed",
        similarity: null,
        threshold: this.threshold,
      },
    });
    if (
      !document.length ||
      !selfie.length ||
      document.length + selfie.length > maxInputBytes
    )
      return failed();
    return new Promise((resolve) => {
      let child: ChildProcessWithoutNullStreams;
      let timer: ReturnType<typeof setTimeout> | undefined;
      let settled = false;
      let size = 0;
      const chunks: Buffer[] = [];
      const terminate = () => {
        // Tesseract is another child of Python. Kill the entire process group so
        // a timeout cannot leave OCR CPU work running after the HTTP response.
        if (process.platform !== "win32" && child?.pid) {
          try {
            process.kill(-child.pid, "SIGKILL");
            return;
          } catch {
            /* Process already exited. */
          }
        }
        try {
          child?.kill("SIGKILL");
        } catch {
          /* Failed launch or exited. */
        }
      };
      const finish = (result: IdentityCheckResult, kill = false) => {
        if (settled) return;
        settled = true;
        if (timer) clearTimeout(timer);
        if (kill) terminate();
        resolve(result);
      };
      try {
        child = this.launch(this.pythonPath, [enginePath], {
          detached: process.platform !== "win32",
          env: {
            ...process.env,
            KYC_LOCAL_MODELS_DIR: this.modelsDir,
            KYC_LOCAL_OCR_LANGUAGES: this.ocrLanguages,
            TESSDATA_PREFIX: join(this.modelsDir, "tessdata"),
          },
          windowsHide: true,
        });
        timer = setTimeout(() => finish(failed(), true), this.timeoutMs);
        child.stderr.resume(); // Drain without retaining provider diagnostics/PII.
        child.on("error", () => finish(failed(), true));
        child.stdin.on("error", () => finish(failed(), true));
        child.stdout.on("error", () => finish(failed(), true));
        child.stderr.on("error", () => finish(failed(), true));
        child.stdout.on("data", (chunk: Buffer) => {
          if (settled) return;
          size += chunk.length;
          if (size > maxOutputBytes) finish(failed(), true);
          else chunks.push(chunk);
        });
        child.on("close", (code) => {
          if (settled) return;
          if (code !== 0) return finish(failed());
          try {
            const result = resultSchema.parse(
              JSON.parse(Buffer.concat(chunks).toString("utf8")),
            );
            const face = result.faceMatch;
            const selfie = result.selfieFace;
            const hasScore =
              face.status === "matched" || face.status === "not_matched";
            if (
              face.threshold !== this.threshold ||
              (selfie.status !== "detected" && face.status !== selfie.status) ||
              (hasScore &&
                (face.similarity === null ||
                  face.status !==
                    (face.similarity >= this.threshold
                      ? "matched"
                      : "not_matched"))) ||
              (!hasScore && face.similarity !== null)
            )
              return finish(failed());
            if (
              result.ocr.status !== "succeeded" &&
              (result.ocr.text !== "" ||
                result.ocr.confidence !== null ||
                Object.values(result.ocr.fields).some(
                  (field) => field !== null,
                ))
            )
              return finish(failed());
            finish(result);
          } catch {
            finish(failed());
          }
        });
        child.stdin.end(
          JSON.stringify({
            document: document.toString("base64"),
            selfie: selfie.toString("base64"),
            threshold: this.threshold,
          }),
        );
      } catch {
        finish(failed(), true);
      }
    });
  }
}
