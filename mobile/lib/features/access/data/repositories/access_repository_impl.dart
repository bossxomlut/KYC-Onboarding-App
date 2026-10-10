import 'dart:typed_data';
import '../../../../core/domain/result.dart';
import '../../../../core/network/api_failure.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/data/models/user_model.dart';
import '../../../kyc/domain/entities/kyc_profile.dart';
import '../../../kyc/data/models/kyc_profile_model.dart';
import '../../domain/entities/access_entities.dart';
import '../../domain/repositories/access_repository.dart';
import '../datasources/access_remote_datasource.dart';
import '../models/access_models.dart';

class AccessRepositoryImpl implements AccessRepository {
  const AccessRepositoryImpl(this._remote);
  final AccessRemoteDataSource _remote;
  Future<Result<T>> _guard<T>(Future<T> Function() operation) async {
    try {
      return Success(await operation());
    } catch (error) {
      return Failure(mapApiFailure(error));
    }
  }

  @override
  Future<Result<User>> currentUser() => _guard(
    () async => UserModel.fromJson(
      (await _remote.currentUser())['user'] as Map<String, dynamic>,
    ).toEntity(),
  );
  @override
  Future<Result<RoleRequest?>> ownRequest() => _guard(() async {
    final value = (await _remote.ownRequest())['request'];
    return value == null
        ? null
        : AccessModels.request(value as Map<String, dynamic>);
  });
  @override
  Future<Result<RoleRequest>> requestReviewer(String reason) => _guard(
    () async => AccessModels.request(
      (await _remote.requestReviewer(reason))['request']
          as Map<String, dynamic>,
    ),
  );
  @override
  Future<Result<PageResult<ManagedUser>>> users({int offset = 0}) =>
      _guard(() async {
        final data = await _remote.users(offset);
        return PageResult(
          items: List.unmodifiable(
            (data['users'] as List).map(
              (json) => AccessModels.managedUser(json as Map<String, dynamic>),
            ),
          ),
          total: data['total'] as int,
          offset: offset,
        );
      });
  @override
  Future<Result<User>> createUser({
    required String email,
    required String password,
    required UserRole role,
  }) => _guard(
    () async => UserModel.fromJson(
      (await _remote.createUser({
            'email': email,
            'password': password,
            'role': role.apiValue,
          }))['user']
          as Map<String, dynamic>,
    ).toEntity(),
  );
  @override
  Future<Result<User>> changeRole(
    String userId,
    UserRole role, {
    String? reason,
  }) => _guard(
    () async => UserModel.fromJson(
      (await _remote.changeRole(userId, {
            'role': role.apiValue,
            'reason': ?reason,
          }))['user']
          as Map<String, dynamic>,
    ).toEntity(),
  );
  @override
  Future<Result<PageResult<RoleRequest>>> requests({int offset = 0}) =>
      _guard(() async {
        final data = await _remote.requests(offset);
        return PageResult(
          items: List.unmodifiable(
            (data['requests'] as List).map(
              (json) => AccessModels.request(json as Map<String, dynamic>),
            ),
          ),
          total: data['total'] as int,
          offset: offset,
        );
      });
  @override
  Future<Result<RoleRequest>> decideRequest(
    String requestId,
    RoleRequestStatus decision, {
    String? reason,
  }) => _guard(
    () async => AccessModels.request(
      (await _remote.decideRequest(requestId, {
            'decision': decision.name,
            if (reason != null && reason.isNotEmpty) 'reason': reason,
          }))['request']
          as Map<String, dynamic>,
    ),
  );
  @override
  Future<Result<PageResult<ReviewSummary>>> reviewQueue({int offset = 0}) =>
      _guard(() async {
        final data = await _remote.reviewQueue(offset);
        return PageResult(
          items: List.unmodifiable(
            (data['profiles'] as List).map(
              (json) => AccessModels.summary(json as Map<String, dynamic>),
            ),
          ),
          total: data['total'] as int,
          offset: offset,
        );
      });
  @override
  Future<Result<ReviewDetail>> reviewDetail(String userId) => _guard(
    () async => AccessModels.detail(await _remote.reviewDetail(userId)),
  );
  @override
  Future<Result<Uint8List>> reviewMedia(
    String userId,
    MediaKind kind, {
    required String submissionId,
  }) => _guard(
    () => _remote.reviewMedia(userId, kind.name, submissionId: submissionId),
  );
  @override
  Future<Result<KycProfile>> decideProfile(
    String userId,
    ReviewDecision decision, {
    required String submissionId,
    String? reason,
    List<KycStep> requiredSteps = const [],
  }) => _guard(
    () async => KycProfileModel.fromJson(
      (await _remote.decideProfile(userId, {
            'submissionId': submissionId,
            'decision': decision.name,
            if (decision == ReviewDecision.rejected) ...{
              'reason': reason,
              'requiredSteps': requiredSteps
                  .map(
                    (step) => switch (step) {
                      KycStep.personalDetails => 'personal_details',
                      _ => step.name,
                    },
                  )
                  .toList(),
            },
          }))['profile']
          as Map<String, dynamic>,
    ),
  );
}
