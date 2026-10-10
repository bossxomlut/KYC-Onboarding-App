import '../../../auth/domain/entities/user.dart';
import '../../../kyc/data/models/kyc_profile_model.dart';
import '../../../kyc/domain/entities/kyc_profile.dart';
import '../../domain/entities/kyc_history.dart';

abstract final class KycHistoryModel {
  static KycHistoryPageResult page(
    Map<String, dynamic> json, {
    required int offset,
  }) => KycHistoryPageResult(
    submissions: List.unmodifiable(
      (json['submissions'] as List).map(
        (value) => submission(value as Map<String, dynamic>),
      ),
    ),
    total: json['total'] as int,
    offset: offset,
  );
  static KycHistorySubmission submission(Map<String, dynamic> json) =>
      KycHistorySubmission(
        id: json['id'] as String,
        version: json['version'] as int,
        profile: KycProfileModel.fromJson(
          json['profile'] as Map<String, dynamic>,
        ),
        review: json['review'] == null
            ? null
            : _review(json['review'] as Map<String, dynamic>),
      );
  static KycHistoryReview _review(Map<String, dynamic> json) =>
      KycHistoryReview(
        decision: switch (json['decision']) {
          'verified' => KycStatus.verified,
          'rejected' => KycStatus.rejected,
          _ => throw const FormatException(
            'Unknown historical review decision',
          ),
        },
        reviewedAt: DateTime.parse(json['reviewedAt'] as String),
        reason: json['reason'] as String?,
        requiredSteps: List.unmodifiable(
          (json['requiredSteps'] as List? ?? []).map(
            (step) => KycProfileModel.step(step as String),
          ),
        ),
        reviewer: json['reviewer'] == null
            ? null
            : _reviewer(json['reviewer'] as Map<String, dynamic>),
      );
  static KycHistoryReviewer _reviewer(Map<String, dynamic> json) =>
      KycHistoryReviewer(
        id: json['id'] as String,
        email: json['email'] as String?,
        role: switch (json['role']) {
          null => null,
          'user' => UserRole.user,
          'reviewer' => UserRole.reviewer,
          'super_admin' => UserRole.superAdmin,
          _ => throw const FormatException('Unknown historical reviewer role'),
        },
      );
}
