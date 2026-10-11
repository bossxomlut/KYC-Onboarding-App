import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/core/domain/result.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';
import 'package:kyc_onboarding/features/kyc/domain/usecases/kyc_usecases.dart';
import 'package:kyc_onboarding/features/kyc/presentation/bloc/kyc_cubit.dart';

import 'kyc_cubit_test.dart' show FakeKycRepository, captured;

void main() {
  late _SubmissionRepository repository;
  late KycCubit cubit;
  setUp(() {
    repository = _SubmissionRepository();
    cubit = KycCubit(
      loadKyc: LoadKyc(repository),
      savePersonalDetails: SavePersonalDetails(repository),
      captureMedia: CaptureMedia(repository),
      uploadMedia: UploadMedia(repository),
      loadPrivateMedia: LoadPrivateMedia(repository),
      submitKyc: SubmitKyc(repository),
      resubmitKyc: ResubmitKyc(repository),
      verifyIdentity: VerifyIdentity(repository),
      recoverCapture: RecoverCapture(repository),
      discardLocalMedia: DiscardLocalMedia(repository),
    );
  });
  tearDown(() => cubit.close());

  test(
    'ordinary submission runs checks first and preserves reviewer evidence',
    () async {
      await cubit.load();
      expect(repository.calls, ['load']);
      expect(await cubit.submit(), isTrue);
      expect(repository.calls, ['load', 'verify', 'submit']);
      expect(
        repository.submitted!.verification!.status,
        VerificationStatus.completed,
      );
      expect(
        repository.submitted!.verification!.selfieFace!.status,
        SelfieFaceStatus.detected,
      );
      expect(cubit.state.profile!.status, KycStatus.pendingReview);
      expect(cubit.state.profile!.verification!.faceMatch!.similarity, 76.4);
      expect(cubit.state.error, isNull);
    },
  );

  test('failed checks are retried during a new submission', () async {
    repository.profile = _profile(checks: VerificationStatus.failed);
    await cubit.load();
    expect(await cubit.submit(), isTrue);
    expect(repository.calls, ['load', 'verify', 'submit']);
    expect(
      repository.submitted!.verification!.status,
      VerificationStatus.completed,
    );
  });

  for (final checks in [
    VerificationStatus.completed,
    VerificationStatus.disabled,
    null,
  ]) {
    test(
      '$checks evidence submits without an optional check request',
      () async {
        repository.profile = _profile(checks: checks);
        await cubit.load();
        expect(await cubit.submit(), isTrue);
        expect(repository.calls, ['load', 'submit']);
        expect(cubit.state.error, isNull);
      },
    );
  }

  for (final code in [
    'NETWORK_ERROR',
    'VERIFICATION_NOT_CONFIGURED',
    'KYC_VERIFICATION_UNAVAILABLE',
    'KYC_VERIFICATION_RATE_LIMITED',
    'SERVER_ERROR',
  ]) {
    test(
      '$code checks failure falls back to manual submission without provider details',
      () async {
        repository.checkResult = Failure(
          AppFailure(code: code, message: 'Private optional provider detail'),
        );
        await cubit.load();
        final states = <KycState>[];
        final subscription = cubit.stream.listen(states.add);
        expect(await cubit.submit(), isTrue);
        await subscription.cancel();
        expect(repository.calls, ['load', 'verify', 'submit']);
        expect(states.every((state) => state.error == null), isTrue);
        expect(cubit.state.profile!.status, KycStatus.pendingReview);
      },
    );
  }

  test(
    'semantic provider failure remains reviewer evidence and allows manual review',
    () async {
      repository.checkResult = Success(
        _profile(checks: VerificationStatus.failed),
      );
      await cubit.load();
      expect(await cubit.submit(), isTrue);
      expect(repository.calls, ['load', 'verify', 'submit']);
      expect(
        repository.submitted!.verification!.status,
        VerificationStatus.failed,
      );
      expect(
        cubit.state.profile!.verification!.status,
        VerificationStatus.failed,
      );
      expect(cubit.state.error, isNull);
    },
  );

  test(
    'submitting stays busy across both calls, deduplicates taps, and queues one refresh',
    () async {
      await cubit.load();
      repository.checkGate = Completer<Result<KycProfile>>();
      repository.submitGate = Completer<void>();
      final states = <KycState>[];
      final subscription = cubit.stream.listen(states.add);
      final submission = cubit.submit();
      expect(cubit.state.busy, isTrue);
      expect(cubit.state.operation, KycOperation.submitting);
      expect(repository.calls, ['load', 'verify']);
      expect(await cubit.submit(), isFalse);
      expect(await cubit.verifyIdentity(), isFalse);
      final refreshOne = cubit.refresh();
      final refreshTwo = cubit.refresh();
      repository.checkGate!.complete(
        Success(_profile(checks: VerificationStatus.completed)),
      );
      await Future<void>.delayed(Duration.zero);
      expect(repository.calls, ['load', 'verify', 'submit']);
      expect(cubit.state.busy, isTrue);
      expect(cubit.state.operation, KycOperation.submitting);
      expect(await cubit.submit(), isFalse);
      repository.submitGate!.complete();
      expect(await submission, isTrue);
      await Future.wait([refreshOne, refreshTwo]);
      await subscription.cancel();
      expect(repository.calls, ['load', 'verify', 'submit', 'load']);
      expect(
        states
            .takeWhile((state) => state.busy)
            .every((state) => state.operation == KycOperation.submitting),
        isTrue,
      );
      expect(cubit.state.operation, KycOperation.none);
    },
  );

  test('closing during checks never starts the following submit', () async {
    await cubit.load();
    repository.checkGate = Completer<Result<KycProfile>>();
    final submission = cubit.submit();
    final refresh = cubit.refresh();
    await cubit.close();
    repository.checkGate!.complete(
      Success(_profile(checks: VerificationStatus.completed)),
    );
    expect(await submission, isFalse);
    await refresh;
    expect(repository.calls, ['load', 'verify']);
  });

  test(
    'a background cycle during checks requires fresh intent after reconciliation',
    () async {
      await cubit.load();
      repository.checkGate = Completer<Result<KycProfile>>();
      final submission = cubit.submit();
      cubit.prepareForResume();
      final refresh = cubit.refresh();
      repository.checkGate!.complete(
        Success(_profile(checks: VerificationStatus.completed)),
      );
      expect(await submission, isFalse);
      await refresh;
      expect(repository.calls, ['load', 'verify', 'load']);
      expect(cubit.state.busy, isFalse);
      expect(cubit.state.profile!.canEdit, isTrue);
    },
  );

  for (final changed in [
    _profile(
      documentId: 'changed-document',
      checks: VerificationStatus.completed,
    ),
    _profile(selfieId: 'changed-selfie', checks: VerificationStatus.completed),
    _profile(id: 'another-profile', checks: VerificationStatus.completed),
    _profile(name: 'Changed details', checks: VerificationStatus.completed),
    _profile(
      status: KycStatus.pendingReview,
      checks: VerificationStatus.completed,
    ),
  ]) {
    test(
      'a changed check response is reconciled without submitting unseen data (${changed.id}/${changed.document!.id}/${changed.selfie!.id}/${changed.status}/${changed.personalDetails!.fullName})',
      () async {
        repository.checkResult = Success(changed);
        await cubit.load();
        expect(await cubit.submit(), isFalse);
        await Future<void>.delayed(Duration.zero);
        expect(repository.calls, ['load', 'verify', 'load']);
        expect(repository.submitted, isNull);
        expect(cubit.state.busy, isFalse);
      },
    );
  }

  for (final code in [
    'SESSION_EXPIRED',
    'UNAUTHORIZED',
    'FORBIDDEN',
    'ACCOUNT_DISABLED',
  ]) {
    test(
      '$code during checks prevents submission and retains the authority error',
      () async {
        repository.checkResult = Failure(
          AppFailure(code: code, message: 'Please sign in again.'),
        );
        await cubit.load();
        expect(await cubit.submit(), isFalse);
        expect(repository.calls, ['load', 'verify']);
        expect(cubit.state.error!.code, code);
        expect(cubit.state.busy, isFalse);
        expect(await cubit.submit(), isFalse);
        expect(repository.calls, ['load', 'verify']);
      },
    );
  }

  test(
    'authority failure in the awaited refresh blocks checking and submitting',
    () async {
      await cubit.load();
      repository.loadGate = Completer<Result<KycProfile>>();
      final refresh = cubit.refresh();
      final submission = cubit.submit();
      repository.loadGate!.complete(
        const Failure(
          AppFailure(code: 'SESSION_EXPIRED', message: 'Please sign in again.'),
        ),
      );
      await refresh;
      expect(await submission, isFalse);
      expect(repository.calls, ['load', 'load']);
      expect(cubit.state.error!.code, 'SESSION_EXPIRED');
    },
  );

  for (final code in [
    'KYC_VERIFICATION_CHANGED',
    'PROFILE_LOCKED',
    'KYC_LOCKED',
    'KYC_VERIFICATION_INCOMPLETE',
  ]) {
    test(
      '$code aborts the stale sequence and refreshes without a submit',
      () async {
        repository.checkResult = Failure(
          AppFailure(code: code, message: 'Optional check stale detail'),
        );
        await cubit.load();
        expect(await cubit.submit(), isFalse);
        await Future<void>.delayed(Duration.zero);
        expect(repository.calls, ['load', 'verify', 'load']);
        expect(repository.submitted, isNull);
        expect(
          cubit.state.error?.message,
          isNot('Optional check stale detail'),
        );
      },
    );
  }

  test(
    'an unuploaded capture still blocks both checks and submission',
    () async {
      repository.recovered = captured;
      await cubit.load();
      expect(await cubit.submit(), isFalse);
      expect(repository.calls, ['load']);
      expect(cubit.state.error!.code, 'INCOMPLETE');
    },
  );

  test('an incomplete profile keeps the normal completion guidance', () async {
    repository.profile = const KycProfile(
      id: 'profile-demo',
      status: KycStatus.inProgress,
      nextStep: KycStep.selfie,
    );
    await cubit.load();
    expect(await cubit.submit(), isFalse);
    expect(repository.calls, ['load']);
    expect(cubit.state.error!.code, 'INCOMPLETE');
  });

  test(
    'a changed server refresh does not submit photos the applicant has not reviewed',
    () async {
      await cubit.load();
      repository.loadGate = Completer<Result<KycProfile>>();
      final refresh = cubit.refresh();
      final submission = cubit.submit();
      repository.loadGate!.complete(Success(_profile(selfieId: 'new-selfie')));
      await refresh;
      expect(await submission, isFalse);
      expect(repository.calls, ['load', 'load']);
      expect(cubit.state.profile!.selfie!.id, 'new-selfie');
      expect(cubit.state.error!.code, 'SUBMISSION_CHANGED');
    },
  );

  test(
    'an unfinished server check exposes generic submit retry guidance with its original code',
    () async {
      repository.checkResult = const Failure(
        AppFailure(code: 'NETWORK_ERROR', message: 'Optional transport detail'),
      );
      repository.submitResult = const Failure(
        AppFailure(
          code: 'KYC_VERIFICATION_IN_PROGRESS',
          message: 'Wait for the identity check to finish before submitting.',
        ),
      );
      await cubit.load();
      expect(await cubit.submit(), isFalse);
      expect(repository.calls, ['load', 'verify', 'submit']);
      expect(cubit.state.error!.code, 'KYC_VERIFICATION_IN_PROGRESS');
      expect(
        cubit.state.error!.message,
        'Your submission could not be completed yet. Please try again.',
      );
    },
  );
}

KycProfile _profile({
  String id = 'profile-demo',
  String documentId = 'document',
  String selfieId = 'selfie',
  String name = 'Demo User',
  KycStatus status = KycStatus.inProgress,
  VerificationStatus? checks = VerificationStatus.notStarted,
}) => KycProfile(
  id: id,
  status: status,
  nextStep: status == KycStatus.pendingReview ? KycStep.result : KycStep.review,
  personalDetails: PersonalDetails(
    fullName: name,
    dateOfBirth: '1995-04-15',
    nationality: 'Vietnamese',
    address: '1 Demo Street',
    documentNumber: 'DEMO1234',
  ),
  document: KycMedia(id: documentId, mimeType: 'image/jpeg', size: 100),
  selfie: KycMedia(id: selfieId, mimeType: 'image/jpeg', size: 100),
  verification: checks == null
      ? null
      : KycVerification(
          provider: checks == VerificationStatus.disabled ? 'none' : 'local',
          status: checks,
          documentId: documentId,
          selfieId: selfieId,
          selfieFace: checks == VerificationStatus.completed
              ? const SelfieFaceVerification(status: SelfieFaceStatus.detected)
              : null,
          faceMatch: checks == VerificationStatus.completed
              ? const FaceMatchVerification(
                  status: FaceMatchStatus.matched,
                  threshold: 36.3,
                  similarity: 76.4,
                )
              : null,
        ),
);

class _SubmissionRepository extends FakeKycRepository {
  _SubmissionRepository() {
    profile = _profile();
  }
  final calls = <String>[];
  Result<KycProfile>? checkResult;
  Result<KycProfile>? submitResult;
  Completer<Result<KycProfile>>? checkGate;
  Completer<Result<KycProfile>>? loadGate;
  Completer<void>? submitGate;
  KycProfile? submitted;

  @override
  Future<Result<KycProfile>> load() async {
    calls.add('load');
    if (loadGate != null) return loadGate!.future;
    return super.load();
  }

  @override
  Future<Result<KycProfile>> verifyIdentity() async {
    calls.add('verify');
    final result = checkGate == null
        ? checkResult ?? Success(_profile(checks: VerificationStatus.completed))
        : await checkGate!.future;
    if (result case Success<KycProfile>(:final value)) profile = value;
    return result;
  }

  @override
  Future<Result<KycProfile>> submit() async {
    calls.add('submit');
    if (submitGate != null) await submitGate!.future;
    if (submitResult != null) return submitResult!;
    submitted = profile;
    profile = KycProfile(
      id: profile.id,
      status: KycStatus.pendingReview,
      nextStep: KycStep.result,
      personalDetails: profile.personalDetails,
      document: profile.document,
      selfie: profile.selfie,
      verification: profile.verification,
    );
    return Success(profile);
  }
}
