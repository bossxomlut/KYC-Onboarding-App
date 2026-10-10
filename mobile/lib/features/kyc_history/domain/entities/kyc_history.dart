import '../../../auth/domain/entities/user.dart';
import '../../../kyc/domain/entities/kyc_profile.dart';

class KycHistoryReviewer {
  const KycHistoryReviewer({required this.id, this.email, this.role});
  final String id;
  final String? email;
  final UserRole? role;
}

class KycHistoryReview {
  const KycHistoryReview({
    required this.decision,
    required this.reviewedAt,
    this.reason,
    this.requiredSteps = const [],
    this.reviewer,
  });
  final KycStatus decision;
  final DateTime reviewedAt;
  final String? reason;
  final List<KycStep> requiredSteps;
  final KycHistoryReviewer? reviewer;
}

class KycHistorySubmission {
  const KycHistorySubmission({
    required this.id,
    required this.version,
    required this.profile,
    this.review,
  });
  final String id;
  final int version;
  final KycProfile profile;
  final KycHistoryReview? review;
}

class KycHistoryPageResult {
  const KycHistoryPageResult({
    required this.submissions,
    required this.total,
    required this.offset,
  });
  final List<KycHistorySubmission> submissions;
  final int total;
  final int offset;
}
