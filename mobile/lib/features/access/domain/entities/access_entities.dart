import '../../../auth/domain/entities/user.dart';
import '../../../kyc/domain/entities/kyc_profile.dart';

enum RoleRequestStatus { pending, approved, rejected }

enum ReviewDecision { verified, rejected }

class RoleRequest {
  const RoleRequest({
    required this.id,
    required this.userId,
    required this.email,
    required this.status,
    required this.reason,
    required this.createdAt,
    this.decisionReason,
    this.decidedAt,
  });
  final String id;
  final String userId;
  final String email;
  final RoleRequestStatus status;
  final String reason;
  final DateTime createdAt;
  final String? decisionReason;
  final DateTime? decidedAt;
}

class ManagedUser {
  const ManagedUser({required this.user, required this.createdAt});
  final User user;
  final DateTime createdAt;
}

class PageResult<T> {
  const PageResult({
    required this.items,
    required this.total,
    required this.offset,
  });
  final List<T> items;
  final int total;
  final int offset;
  bool get hasMore => offset + items.length < total;
}

class ReviewSummary {
  const ReviewSummary({
    required this.userId,
    required this.email,
    required this.submittedAt,
  });
  final String userId;
  final String email;
  final DateTime? submittedAt;
}

class ReviewDetail {
  const ReviewDetail({
    required this.userId,
    required this.email,
    required this.profile,
  });
  final String userId;
  final String email;
  final KycProfile profile;
}
