import '../../domain/entities/kyc_verification.dart';

abstract final class KycVerificationModel {
  static KycVerification fromJson(Map<String, dynamic> json) {
    final ocr = json['ocr'] as Map<String, dynamic>?;
    final face = json['faceMatch'] as Map<String, dynamic>?;
    final provider = json['provider'] as String;
    if (provider != 'aws' && provider != 'none') {
      throw const FormatException('Unknown identity checks provider');
    }
    return KycVerification(
      provider: provider,
      status: switch (json['status']) {
        'disabled' => VerificationStatus.disabled,
        'not_started' => VerificationStatus.notStarted,
        'completed' => VerificationStatus.completed,
        'failed' => VerificationStatus.failed,
        _ => throw const FormatException('Unknown identity checks status'),
      },
      documentId: json['documentId'] as String?,
      selfieId: json['selfieId'] as String?,
      checkedAt: DateTime.tryParse(json['checkedAt'] as String? ?? ''),
      ocr: ocr == null ? null : _ocr(ocr),
      faceMatch: face == null ? null : _face(face),
    );
  }

  static OcrVerification _ocr(Map<String, dynamic> json) {
    final fields = json['fields'] as Map<String, dynamic>;
    return OcrVerification(
      status: switch (json['status']) {
        'succeeded' => OcrStatus.succeeded,
        'no_text' => OcrStatus.noText,
        'failed' => OcrStatus.failed,
        _ => throw const FormatException('Unknown document text status'),
      },
      text: json['text'] as String,
      fields: OcrFields(
        fullName: fields['fullName'] as String?,
        dateOfBirth: fields['dateOfBirth'] as String?,
        documentNumber: fields['documentNumber'] as String?,
      ),
      confidence: _score(json['confidence']),
    );
  }

  static FaceMatchVerification _face(Map<String, dynamic> json) =>
      FaceMatchVerification(
        status: switch (json['status']) {
          'matched' => FaceMatchStatus.matched,
          'not_matched' => FaceMatchStatus.notMatched,
          'no_face' => FaceMatchStatus.noFace,
          'multiple_faces' => FaceMatchStatus.multipleFaces,
          'failed' => FaceMatchStatus.failed,
          _ => throw const FormatException('Unknown face comparison status'),
        },
        similarity: _score(json['similarity']),
        threshold: _score(json['threshold'])!,
      );

  static double? _score(Object? value) {
    if (value == null) return null;
    final score = (value as num).toDouble();
    if (!score.isFinite || score < 0 || score > 100) {
      throw const FormatException('Invalid identity checks score');
    }
    return score;
  }
}
