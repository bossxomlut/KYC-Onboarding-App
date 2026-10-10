import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/core/domain/result.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';
import 'package:kyc_onboarding/features/kyc/domain/repositories/kyc_repository.dart';
import 'package:kyc_onboarding/features/kyc/domain/usecases/kyc_usecases.dart';
import 'package:kyc_onboarding/features/kyc/presentation/bloc/kyc_cubit.dart';

void main() {
  late FakeKycRepository repository;
  late KycCubit cubit;
  setUp(() {
    repository = FakeKycRepository();
    cubit = KycCubit(
      loadKyc: LoadKyc(repository),
      savePersonalDetails: SavePersonalDetails(repository),
      captureMedia: CaptureMedia(repository),
      uploadMedia: UploadMedia(repository),
      loadPrivateMedia: LoadPrivateMedia(repository),
      submitKyc: SubmitKyc(repository),
      resubmitKyc: ResubmitKyc(repository),
      recoverCapture: RecoverCapture(repository),
      discardLocalMedia: DiscardLocalMedia(repository),
    );
  });
  tearDown(() => cubit.close());

  test(
    'resume follows backend nextStep and failed reload retains profile',
    () async {
      repository.profile = profile(step: KycStep.selfie);
      await cubit.load();
      expect(cubit.state.profile!.nextStep.routePath, '/kyc/selfie');
      repository.loadFailure = true;
      await cubit.load();
      expect(cubit.state.profile!.nextStep, KycStep.selfie);
      expect(cubit.state.error!.isNetwork, isTrue);
    },
  );

  test(
    'failed upload retains capture and retry advances only after server success',
    () async {
      await cubit.load();
      repository.uploadFailure = true;
      await cubit.capture(
        MediaKind.document,
        documentType: DocumentType.passport,
      );
      expect(cubit.state.pendingCaptures[MediaKind.document], isNotNull);
      expect(cubit.state.profile!.nextStep, KycStep.document);
      expect(repository.deleted, isFalse);
      repository.uploadFailure = false;
      await cubit.retryUpload(MediaKind.document);
      expect(cubit.state.pendingCaptures, isEmpty);
      expect(cubit.state.profile!.nextStep, KycStep.selfie);
      expect(repository.deleted, isTrue);
      expect(cubit.state.reviewMedia[MediaKind.document], captured.bytes);
    },
  );

  test(
    'cold restart recovers private pending media belonging to current profile',
    () async {
      repository.recovered = captured;
      await cubit.load();
      expect(
        cubit.state.pendingCaptures[MediaKind.document]!.filePath,
        captured.filePath,
      );
      expect(cubit.state.profile!.nextStep, KycStep.document);
    },
  );

  test('rejected resubmission adopts required step from server', () async {
    repository.profile = profile(
      status: KycStatus.rejected,
      step: KycStep.result,
    );
    await cubit.load();
    await cubit.resubmit();
    expect(cubit.state.profile!.status, KycStatus.inProgress);
    expect(cubit.state.profile!.nextStep, KycStep.selfie);
  });

  test('invalid calendar date fails before saving PII remotely', () async {
    final result = await SavePersonalDetails(repository)(
      const PersonalDetails(
        fullName: 'Demo User',
        dateOfBirth: '2000-02-31',
        nationality: 'Vietnam',
        address: '1 Demo Street',
        documentNumber: 'DEMO1234',
      ),
    );
    expect(result, isA<Failure<KycProfile>>());
    expect(repository.saved, isFalse);
  });

  test(
    'adult-only validation rejects an underage applicant before remote save',
    () async {
      final result =
          await SavePersonalDetails(
            repository,
            now: () => DateTime(2026, 10, 10),
          )(
            const PersonalDetails(
              fullName: 'Demo User',
              dateOfBirth: '2015-04-15',
              nationality: 'Vietnamese',
              address: 'Short',
              documentNumber: 'ABC',
            ),
          );
      expect(result, isA<Failure<KycProfile>>());
      expect(repository.saved, isFalse);
    },
  );

  test('pending review prevents capture and allows status refresh', () async {
    repository.profile = profile(
      status: KycStatus.pendingReview,
      step: KycStep.result,
    );
    await cubit.load();
    await cubit.capture(MediaKind.selfie);
    expect(repository.captureCount, 0);
    expect(cubit.state.error!.code, 'PROFILE_LOCKED');
    repository.profile = profile(
      status: KycStatus.verified,
      step: KycStep.result,
    );
    await cubit.load();
    expect(cubit.state.profile!.status, KycStatus.verified);
  });
}

KycProfile profile({
  KycStatus status = KycStatus.inProgress,
  KycStep step = KycStep.document,
}) => KycProfile(id: 'profile-demo', status: status, nextStep: step);

final captured = CapturedMedia(
  kind: MediaKind.document,
  filePath: '/private/demo.jpg',
  bytes: Uint8List.fromList([1, 2]),
  documentType: DocumentType.passport,
);

class FakeKycRepository implements KycRepository {
  KycProfile profile = KycProfile(
    id: 'profile-demo',
    status: KycStatus.inProgress,
    nextStep: KycStep.document,
  );
  bool loadFailure = false;
  bool uploadFailure = false;
  bool deleted = false;
  bool saved = false;
  int captureCount = 0;
  CapturedMedia? recovered;
  @override
  Future<Result<KycProfile>> load() async => loadFailure
      ? const Failure(
          AppFailure(code: 'NETWORK_ERROR', message: 'Connection interrupted.'),
        )
      : Success(profile);
  @override
  Future<Result<KycProfile>> saveDetails(PersonalDetails details) async {
    saved = true;
    return Success(profile);
  }

  @override
  Future<Result<CapturedMedia?>> capture(
    MediaKind kind,
    String profileId, {
    DocumentType? documentType,
  }) async {
    captureCount++;
    return Success(captured);
  }

  @override
  Future<Result<KycProfile>> upload(
    CapturedMedia media, {
    void Function(int, int)? onProgress,
  }) async {
    if (uploadFailure) {
      return const Failure(
        AppFailure(code: 'NETWORK_ERROR', message: 'Connection interrupted.'),
      );
    }
    onProgress?.call(100, 100);
    deleted = true;
    profile = KycProfile(
      id: 'profile-demo',
      status: KycStatus.inProgress,
      nextStep: KycStep.selfie,
    );
    return Success(profile);
  }

  @override
  Future<Result<CapturedMedia?>> recover(
    MediaKind kind,
    String profileId, {
    String? confirmedCaptureId,
  }) async => Success(kind == MediaKind.document ? recovered : null);
  @override
  Future<Result<Uint8List>> privateMedia(MediaKind kind) async =>
      Success(Uint8List(0));
  @override
  Future<Result<KycProfile>> submit() async => Success(profile);
  @override
  Future<Result<KycProfile>> resubmit() async {
    profile = KycProfile(
      id: 'profile-demo',
      status: KycStatus.inProgress,
      nextStep: KycStep.selfie,
    );
    return Success(profile);
  }

  @override
  Future<Result<void>> discardLocal(String profileId) async =>
      const Success(null);
}
