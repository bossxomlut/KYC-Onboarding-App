import '../../domain/entities/kyc_profile.dart';

class KycProfileModel {
  static KycProfile fromJson(Map<String, dynamic> json) {
    final details = json['personalDetails'] as Map<String, dynamic>?;
    return KycProfile(
      id: json['id'] as String,
      status: _status(json['status'] as String),
      nextStep: step(json['nextStep'] as String),
      personalDetails: details == null
          ? null
          : PersonalDetails(
              fullName: details['fullName'] as String,
              dateOfBirth: details['dateOfBirth'] as String,
              nationality: details['nationality'] as String,
              address: details['address'] as String,
              documentNumber: details['documentNumber'] as String,
            ),
      document: _media(json['document'] as Map<String, dynamic>?),
      selfie: _media(json['selfie'] as Map<String, dynamic>?),
      rejectionReason: json['rejectionReason'] as String?,
      requiredSteps: List<KycStep>.unmodifiable(
        (json['requiredSteps'] as List? ?? []).map((e) => step(e as String)),
      ),
      submittedAt: DateTime.tryParse(json['submittedAt'] as String? ?? ''),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    );
  }

  static KycStatus _status(String value) => switch (value) {
        'not_started' => KycStatus.notStarted,
        'in_progress' => KycStatus.inProgress,
        'pending_review' => KycStatus.pendingReview,
        'verified' => KycStatus.verified,
        'rejected' => KycStatus.rejected,
        _ => throw const FormatException('Unknown KYC status'),
      };
  static KycStep step(String value) => switch (value) {
        'personal_details' => KycStep.personalDetails,
        'document' => KycStep.document,
        'selfie' => KycStep.selfie,
        'review' => KycStep.review,
        'result' => KycStep.result,
        _ => throw const FormatException('Unknown KYC step'),
      };
  static KycMedia? _media(Map<String, dynamic>? json) => json == null
      ? null
      : KycMedia(
          id: json['id'] as String,
          mimeType: json['mimeType'] as String,
          size: json['size'] as int,
          captureId: json['captureId'] as String?,
          documentType: json['documentType'] == null
              ? null
              : DocumentType.values.firstWhere(
                  (e) => e.apiValue == json['documentType'],
                ),
        );
  static Map<String, dynamic> detailsJson(PersonalDetails d) => {
        'fullName': d.fullName.trim(),
        'dateOfBirth': d.dateOfBirth,
        'nationality': d.nationality.trim(),
        'address': d.address.trim(),
        'documentNumber': d.documentNumber.trim(),
      };
}
