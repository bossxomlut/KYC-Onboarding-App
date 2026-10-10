import 'dart:typed_data';

enum KycStatus {
  notStarted('Not started'),
  inProgress('In progress'),
  pendingReview('Pending review'),
  verified('Verified'),
  rejected('Rejected');

  const KycStatus(this.label);
  final String label;
}

enum KycStep {
  personalDetails('Personal details', '/kyc/details'),
  document('ID document', '/kyc/document'),
  selfie('Selfie', '/kyc/selfie'),
  review('Review & submit', '/kyc/review'),
  result('Verification result', '/kyc/status');

  const KycStep(this.label, this.routePath);
  final String label;
  final String routePath;
}

enum MediaKind { document, selfie }

enum DocumentType {
  passport('passport', 'Passport'),
  nationalId('national_id', 'National ID'),
  drivingLicence('driving_licence', 'Driving licence');

  const DocumentType(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

class PersonalDetails {
  const PersonalDetails({
    required this.fullName,
    required this.dateOfBirth,
    required this.nationality,
    required this.address,
    required this.documentNumber,
  });
  final String fullName;
  final String dateOfBirth;
  final String nationality;
  final String address;
  final String documentNumber;

  Map<String, String> validate(DateTime now) {
    final errors = <String, String>{};
    if (fullName.trim().length < 2 || fullName.trim().length > 120) {
      errors['fullName'] = 'Enter your full name (2–120 characters).';
    }
    final date = DateTime.tryParse(dateOfBirth);
    final validDate = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dateOfBirth) &&
        date != null &&
        date.toIso8601String().substring(0, 10) == dateOfBirth &&
        date.isBefore(DateTime(now.year, now.month, now.day)) &&
        date.year >= 1900;
    if (!validDate) {
      errors['dateOfBirth'] = 'Enter a valid past date as YYYY-MM-DD.';
    } else {
      var age = now.year - date.year;
      if (now.month < date.month ||
          (now.month == date.month && now.day < date.day)) {
        age--;
      }
      if (age < 18 || age > 120) {
        errors['dateOfBirth'] =
            'Verification is available for adults aged 18–120.';
      }
    }
    if (nationality.trim().length < 2 || nationality.length > 80) {
      errors['nationality'] = 'Enter your nationality.';
    }
    if (address.trim().length < 8 || address.length > 500) {
      errors['address'] = 'Enter your residential address (8–500 characters).';
    }
    if (!RegExp(r'^[A-Za-z0-9 -]{4,40}$').hasMatch(documentNumber.trim())) {
      errors['documentNumber'] =
          'Use 4–40 letters, numbers, spaces or hyphens.';
    }
    return errors;
  }
}

class KycMedia {
  const KycMedia({
    required this.id,
    required this.mimeType,
    required this.size,
    this.documentType,
    this.captureId,
  });
  final String id;
  final String mimeType;
  final int size;
  final DocumentType? documentType;
  final String? captureId;
}

class CapturedMedia {
  const CapturedMedia({
    required this.kind,
    required this.filePath,
    required this.bytes,
    this.documentType,
    this.captureId,
  });
  final MediaKind kind;
  final String filePath;
  final Uint8List bytes;
  final DocumentType? documentType;
  final String? captureId;
}

class KycProfile {
  const KycProfile({
    required this.id,
    required this.status,
    required this.nextStep,
    this.personalDetails,
    this.document,
    this.selfie,
    this.rejectionReason,
    this.requiredSteps = const [],
    this.submittedAt,
    this.updatedAt,
  });
  final String id;
  final KycStatus status;
  final KycStep nextStep;
  final PersonalDetails? personalDetails;
  final KycMedia? document;
  final KycMedia? selfie;
  final String? rejectionReason;
  final List<KycStep> requiredSteps;
  final DateTime? submittedAt;
  final DateTime? updatedAt;
  bool get canEdit =>
      status == KycStatus.notStarted || status == KycStatus.inProgress;
  bool get canSubmit =>
      canEdit && personalDetails != null && document != null && selfie != null;
}
