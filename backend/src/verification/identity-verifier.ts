export interface OcrResult {
  status: "succeeded" | "no_text" | "failed";
  text: string;
  fields: {
    fullName: string | null;
    dateOfBirth: string | null;
    documentNumber: string | null;
  };
  confidence: number | null;
}

export interface FaceMatchResult {
  status: "matched" | "not_matched" | "no_face" | "multiple_faces" | "failed";
  similarity: number | null;
  threshold: number;
}

/** Face presence in the selfie, independently of the document/comparison.
 * Detection is not a liveness or identity authenticity check. */
export interface SelfieFaceResult {
  status: "detected" | "no_face" | "multiple_faces" | "failed";
}

export interface IdentityCheckResult {
  ocr: OcrResult;
  selfieFace: SelfieFaceResult;
  faceMatch: FaceMatchResult;
}

/** Stateless comparison of two already sanitized, private images. */
export interface IdentityVerifier {
  verify(document: Buffer, selfie: Buffer): Promise<IdentityCheckResult>;
}
