enum VerificationStatus { disabled, notStarted, completed, failed }

enum OcrStatus { succeeded, noText, failed }

enum SelfieFaceStatus { detected, noFace, multipleFaces, failed }

enum FaceMatchStatus { matched, notMatched, noFace, multipleFaces, failed }

/// Advisory checks on the photos; a reviewer still decides the KYC outcome.
class KycVerification {
  const KycVerification({
    required this.provider,
    required this.status,
    this.documentId,
    this.selfieId,
    this.checkedAt,
    this.ocr,
    this.selfieFace,
    this.faceMatch,
  });
  final String provider;
  final VerificationStatus status;
  final String? documentId;
  final String? selfieId;
  final DateTime? checkedAt;
  final OcrVerification? ocr;
  final SelfieFaceVerification? selfieFace;
  final FaceMatchVerification? faceMatch;
}

/// Face detection in the selfie; it does not establish liveness or identity.
class SelfieFaceVerification {
  const SelfieFaceVerification({required this.status});
  final SelfieFaceStatus status;
}

class OcrFields {
  const OcrFields({this.fullName, this.dateOfBirth, this.documentNumber});
  final String? fullName;
  final String? dateOfBirth;
  final String? documentNumber;
}

class OcrVerification {
  const OcrVerification({
    required this.status,
    required this.text,
    required this.fields,
    this.confidence,
  });
  final OcrStatus status;
  final String text;
  final OcrFields fields;

  /// OCR engine confidence on a 0–100 scale; not a guarantee of correctness.
  final double? confidence;
}

class FaceMatchVerification {
  const FaceMatchVerification({
    required this.status,
    required this.threshold,
    this.similarity,
  });
  final FaceMatchStatus status;

  /// Advisory similarity on a 0–100 scale, not an identity probability.
  final double? similarity;
  final double threshold;
}
