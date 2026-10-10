import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/core/domain/result.dart';
import 'package:kyc_onboarding/features/auth/domain/entities/user.dart';
import 'package:kyc_onboarding/features/access/domain/entities/access_entities.dart';
import 'package:kyc_onboarding/features/access/domain/repositories/access_repository.dart';
import 'package:kyc_onboarding/features/access/domain/usecases/access_usecases.dart';
import 'package:kyc_onboarding/features/access/presentation/bloc/access_cubit.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';

class FakeAccessRepository implements AccessRepository {
  int requestCount = 0;
  int decisions = 0;
  bool forbidden = false;
  String failureCode = 'FORBIDDEN';
  @override
  Future<Result<User>> currentUser() async => const Success(
    User(
      id: 'r',
      email: 'r@example.test',
      emailVerified: true,
      role: UserRole.reviewer,
    ),
  );
  @override
  Future<Result<RoleRequest?>> ownRequest() async => const Success(null);
  @override
  Future<Result<RoleRequest>> requestReviewer(String reason) async {
    requestCount++;
    return Success(
      RoleRequest(
        id: 'request',
        userId: 'r',
        email: 'r@example.test',
        status: RoleRequestStatus.pending,
        reason: reason,
        createdAt: DateTime(2026),
      ),
    );
  }

  @override
  Future<Result<ReviewDetail>> reviewDetail(String userId) async => forbidden
      ? Failure(AppFailure(code: failureCode, message: 'Permission revoked'))
      : Success(
          ReviewDetail(
            userId: userId,
            email: 'sample@example.test',
            profile: const KycProfile(
              id: 'p',
              status: KycStatus.pendingReview,
              nextStep: KycStep.result,
              document: KycMedia(id: 'doc', mimeType: 'image/jpeg', size: 2),
            ),
          ),
        );
  @override
  Future<Result<Uint8List>> reviewMedia(String userId, MediaKind kind) async =>
      Success(Uint8List.fromList([1, 2]));
  @override
  Future<Result<KycProfile>> decideProfile(
    String userId,
    ReviewDecision decision, {
    String? reason,
    List<KycStep> requiredSteps = const [],
  }) async {
    decisions++;
    return const Success(
      KycProfile(id: 'p', status: KycStatus.verified, nextStep: KycStep.result),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'invalid requests and incomplete rejection cannot reach repository',
    () async {
      final repository = FakeAccessRepository();
      final cubit = AccessCubit(AccessUseCases(repository));
      expect(await cubit.requestReviewer('short'), isFalse);
      expect(repository.requestCount, 0);
      expect(cubit.state.error?.code, 'VALIDATION');
      expect(
        await cubit.requestReviewer('I review identity documents.'),
        isTrue,
      );
      expect(repository.requestCount, 1);
      expect(cubit.state.request?.status, RoleRequestStatus.pending);
      expect(
        await cubit.decideProfile(
          'u',
          ReviewDecision.rejected,
          reason: 'bad',
          requiredSteps: [],
        ),
        isFalse,
      );
      expect(repository.decisions, 0);
      await cubit.close();
    },
  );
  test(
    'revoked reviewer permission clears displayed private information',
    () async {
      final repository = FakeAccessRepository();
      final cubit = AccessCubit(AccessUseCases(repository));
      await cubit.loadDetail('u');
      expect(cubit.state.detail?.email, 'sample@example.test');
      expect(cubit.state.media, isNotEmpty);
      repository.forbidden = true;
      await cubit.loadDetail('u');
      expect(cubit.state.detail, isNull);
      expect(cubit.state.media, isEmpty);
      expect(cubit.state.error?.code, 'FORBIDDEN');
      await cubit.close();
    },
  );
  test('self review is rejected by use case before network', () async {
    final repository = FakeAccessRepository();
    final usecases = AccessUseCases(repository);
    final result = await usecases.decideProfile(
      'r',
      ReviewDecision.verified,
      actorId: 'r',
    );
    expect(result, isA<Failure<KycProfile>>());
    expect(repository.decisions, 0);
  });
  for (final code in [
    'SELF_REVIEW_FORBIDDEN',
    'KYC_REVIEW_NOT_FOUND',
    'KYC_REVIEW_NOT_PENDING',
    'SESSION_EXPIRED',
  ]) {
    test('$code clears private reviewer details and images', () async {
      final repository = FakeAccessRepository()..failureCode = code;
      final cubit = AccessCubit(AccessUseCases(repository));
      await cubit.loadDetail('u');
      expect(cubit.state.detail, isNotNull);
      repository.forbidden = true;
      await cubit.loadDetail('u');
      expect(cubit.state.detail, isNull);
      expect(cubit.state.media, isEmpty);
      expect(cubit.state.error?.code, code);
      await cubit.close();
    });
  }
  for (final operation in ['create', 'role', 'request']) {
    test(
      'successful $operation preserves an error from refreshing account lists',
      () async {
        final cubit = AccessCubit(AccessUseCases(_ReloadFailureRepository()));
        final bool saved;
        switch (operation) {
          case 'create':
            saved = await cubit.createUser(
              'u@example.test',
              'FakePassword123',
              UserRole.user,
            );
          case 'role':
            saved = await cubit.changeRole('u', UserRole.reviewer);
          default:
            saved = await cubit.decideRequest(
              'request',
              RoleRequestStatus.approved,
            );
        }
        expect(saved, isTrue);
        expect(cubit.state.error?.isNetwork, isTrue);
        expect(cubit.state.message, isNotNull);
        expect(cubit.state.busy, isFalse);
        await cubit.close();
      },
    );
  }
}

class _ReloadFailureRepository extends FakeAccessRepository {
  @override
  Future<Result<PageResult<ManagedUser>>> users({int offset = 0}) async =>
      const Failure(
        AppFailure(code: 'NETWORK_ERROR', message: 'Refresh failed'),
      );
  @override
  Future<Result<User>> createUser({
    required String email,
    required String password,
    required UserRole role,
  }) async =>
      Success(User(id: 'u', email: email, emailVerified: false, role: role));
  @override
  Future<Result<User>> changeRole(
    String userId,
    UserRole role, {
    String? reason,
  }) async => Success(
    User(id: userId, email: 'u@example.test', emailVerified: true, role: role),
  );
  @override
  Future<Result<RoleRequest>> decideRequest(
    String requestId,
    RoleRequestStatus decision, {
    String? reason,
  }) async => Success(
    RoleRequest(
      id: requestId,
      userId: 'u',
      email: 'u@example.test',
      status: decision,
      reason: 'I review identity documents.',
      createdAt: DateTime(2026),
    ),
  );
}
