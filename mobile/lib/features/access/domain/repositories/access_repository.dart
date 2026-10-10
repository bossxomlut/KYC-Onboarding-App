import 'dart:typed_data';
import '../../../../core/domain/result.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../kyc/domain/entities/kyc_profile.dart';
import '../entities/access_entities.dart';

abstract interface class AccessRepository {
  Future<Result<User>> currentUser();
  Future<Result<RoleRequest?>> ownRequest();
  Future<Result<RoleRequest>> requestReviewer(String reason);
  Future<Result<PageResult<ManagedUser>>> users({int offset = 0});
  Future<Result<User>> createUser({
    required String email,
    required String password,
    required UserRole role,
  });
  Future<Result<User>> changeRole(
    String userId,
    UserRole role, {
    String? reason,
  });
  Future<Result<PageResult<RoleRequest>>> requests({int offset = 0});
  Future<Result<RoleRequest>> decideRequest(
    String requestId,
    RoleRequestStatus decision, {
    String? reason,
  });
  Future<Result<PageResult<ReviewSummary>>> reviewQueue({int offset = 0});
  Future<Result<ReviewDetail>> reviewDetail(String userId);
  Future<Result<Uint8List>> reviewMedia(
    String userId,
    MediaKind kind, {
    required String submissionId,
  });
  Future<Result<KycProfile>> decideProfile(
    String userId,
    ReviewDecision decision, {
    required String submissionId,
    String? reason,
    List<KycStep> requiredSteps = const [],
  });
}
