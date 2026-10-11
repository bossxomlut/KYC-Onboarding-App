import '../../../auth/data/models/user_model.dart';
import '../../../kyc/data/models/kyc_profile_model.dart';
import '../../../kyc/domain/entities/kyc_profile.dart';
import '../../domain/entities/access_entities.dart';

abstract final class AccessModels {
  static RoleRequest request(Map<String, dynamic> json) => RoleRequest(
    id: json['id'] as String,
    userId: json['userId'] as String,
    email: json['email'] as String,
    status: switch (json['status']) {
      'pending' => RoleRequestStatus.pending,
      'approved' => RoleRequestStatus.approved,
      'rejected' => RoleRequestStatus.rejected,
      _ => throw const FormatException('Unknown permission request status'),
    },
    reason: json['reason'] as String,
    decisionReason: json['decisionReason'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
    decidedAt: DateTime.tryParse(json['decidedAt'] as String? ?? ''),
  );
  static ManagedUser managedUser(Map<String, dynamic> json) => ManagedUser(
    user: UserModel.fromJson(json).toEntity(),
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
  static ReviewSummary summary(Map<String, dynamic> json) => ReviewSummary(
    userId: json['userId'] as String,
    email: json['email'] as String,
    status: switch (json['status']) {
      'pending_review' => KycStatus.pendingReview,
      'verified' => KycStatus.verified,
      'rejected' => KycStatus.rejected,
      _ => throw const FormatException('Unknown review profile status'),
    },
    submittedAt: DateTime.tryParse(json['submittedAt'] as String? ?? ''),
  );
  static ReviewDetail detail(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>;
    return ReviewDetail(
      submissionId: json['submissionId'] as String,
      userId: user['id'] as String,
      email: user['email'] as String,
      profile: KycProfileModel.fromJson(
        json['profile'] as Map<String, dynamic>,
      ),
    );
  }
}
