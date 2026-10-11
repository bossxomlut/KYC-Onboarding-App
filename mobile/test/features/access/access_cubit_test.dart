import 'dart:async';
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
  String detailSubmissionId = 'submission-1';
  final mediaSubmissionIds = <String>[];
  String? decidedSubmissionId;
  Completer<void>? decisionGate;
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
            submissionId: detailSubmissionId,
            userId: userId,
            email: 'sample@example.test',
            profile: const KycProfile(
              id: 'p',
              status: KycStatus.pendingReview,
              nextStep: KycStep.result,
              document: KycMedia(id: 'doc', mimeType: 'image/jpeg', size: 2),
              selfie: KycMedia(id: 'selfie', mimeType: 'image/jpeg', size: 2),
            ),
          ),
        );
  @override
  Future<Result<Uint8List>> reviewMedia(
    String userId,
    MediaKind kind, {
    required String submissionId,
  }) async {
    mediaSubmissionIds.add(submissionId);
    return Success(Uint8List.fromList([1, 2]));
  }

  @override
  Future<Result<KycProfile>> decideProfile(
    String userId,
    ReviewDecision decision, {
    required String submissionId,
    String? reason,
    List<KycStep> requiredSteps = const [],
  }) async {
    decisions++;
    decidedSubmissionId = submissionId;
    if (decisionGate != null) await decisionGate!.future;
    return const Success(
      KycProfile(id: 'p', status: KycStatus.verified, nextStep: KycStep.result),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'fresh role is published even when the role request fails to load',
    () async {
      final cubit = AccessCubit(AccessUseCases(_PartialAccessRepository()));
      await cubit.loadAccess();
      expect(cubit.state.user?.role, UserRole.reviewer);
      expect(cubit.state.error?.code, 'NETWORK_ERROR');
      await cubit.close();
    },
  );
  test(
    'background blocks decisions until the same submission has revalidated',
    () async {
      final repository = FakeAccessRepository();
      final cubit = AccessCubit(AccessUseCases(repository));
      await cubit.loadDetail('u');
      cubit.prepareForResume();
      expect(cubit.state.needsRevalidation, isTrue);
      expect(
        await cubit.decideProfile(
          'u',
          ReviewDecision.verified,
          submissionId: 'submission-1',
        ),
        isFalse,
      );
      expect(repository.decisions, 0);
      await cubit.loadDetail('u');
      expect(cubit.state.needsRevalidation, isFalse);
      expect(repository.mediaSubmissionIds.toSet(), {'submission-1'});
      repository.detailSubmissionId = 'submission-2';
      cubit.prepareForResume();
      await cubit.loadDetail('u');
      expect(
        await cubit.decideProfile(
          'u',
          ReviewDecision.verified,
          submissionId: 'submission-1',
        ),
        isFalse,
      );
      expect(repository.decisions, 0);
      expect(cubit.state.error?.code, 'KYC_REVIEW_CHANGED');
      expect(cubit.state.detail, isNull);
      expect(cubit.state.media, isEmpty);
      await cubit.close();
    },
  );

  test(
    'resume queues a trailing refresh and ignores the pre-background read',
    () async {
      final repository = _DeferredQueueRepository();
      final cubit = AccessCubit(AccessUseCases(repository));
      final initial = cubit.loadQueue(offset: 50);
      cubit.prepareForResume();
      final resumed = cubit.loadQueue(offset: 50);
      expect(repository.offsets, [50]);
      repository.gates[0].complete();
      await Future<void>.delayed(Duration.zero);
      expect(repository.offsets, [50, 50]);
      expect(cubit.state.needsRevalidation, isTrue);
      expect(cubit.state.queue, isNull);
      repository.gates[1].complete();
      await Future.wait([initial, resumed]);
      expect(cubit.state.queue!.items.single.email, 'round-2@example.test');
      expect(cubit.state.queue!.offset, 50);
      expect(cubit.state.needsRevalidation, isFalse);
      expect(cubit.state.busy, isFalse);
      await cubit.close();
    },
  );

  test(
    'a committed decision is retained when background interrupts its response',
    () async {
      final repository = FakeAccessRepository()
        ..decisionGate = Completer<void>();
      final cubit = AccessCubit(AccessUseCases(repository));
      await cubit.loadDetail('u');
      final decision = cubit.decideProfile(
        'u',
        ReviewDecision.verified,
        submissionId: 'submission-1',
      );
      cubit.prepareForResume();
      repository.decisionGate!.complete();
      expect(await decision, isTrue);
      expect(repository.decisions, 1);
      expect(repository.decidedSubmissionId, 'submission-1');
      expect(cubit.state.message, 'Review decision saved.');
      expect(cubit.state.needsRevalidation, isTrue);
      expect(cubit.state.media, isEmpty);
      await cubit.close();
    },
  );

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
      await cubit.loadDetail('u');
      expect(
        await cubit.decideProfile(
          'u',
          ReviewDecision.rejected,
          submissionId: 'submission-1',
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
      submissionId: 'submission-1',
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

class _PartialAccessRepository extends FakeAccessRepository {
  @override
  Future<Result<RoleRequest?>> ownRequest() async => const Failure(
    AppFailure(code: 'NETWORK_ERROR', message: 'Request status unavailable'),
  );
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

class _DeferredQueueRepository extends FakeAccessRepository {
  final offsets = <int>[];
  final gates = [Completer<void>(), Completer<void>()];
  @override
  Future<Result<PageResult<ReviewSummary>>> reviewQueue({
    int offset = 0,
    ReviewFilter filter = ReviewFilter.pending,
    String search = '',
  }) async {
    offsets.add(offset);
    final call = offsets.length;
    await gates[call - 1].future;
    return Success(
      PageResult(
        items: [
          ReviewSummary(
            userId: 'u',
            email: 'round-$call@example.test',
            submittedAt: null,
          ),
        ],
        total: 51,
        offset: offset,
      ),
    );
  }
}
