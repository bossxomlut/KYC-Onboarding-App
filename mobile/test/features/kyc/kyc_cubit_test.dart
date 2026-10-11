import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/core/domain/result.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/camera_capture_crop.dart';
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
      verifyIdentity: VerifyIdentity(repository),
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

  test('deferred capture retains draft until an explicit upload', () async {
    await cubit.load();
    final crop = CameraCaptureCrop.fromViewport(
      viewportWidth: 390,
      viewportHeight: 844,
      frameLeft: 24,
      frameTop: 240,
      frameWidth: 342,
      frameHeight: 240,
      previewAspectRatio: .75,
    );

    final saved = await cubit.capture(
      MediaKind.document,
      documentType: DocumentType.passport,
      uploadImmediately: false,
      crop: crop,
    );

    expect(saved, isTrue);
    expect(repository.captureCount, 1);
    expect(repository.receivedCrop, same(crop));
    expect(repository.observedUploads, 0);
    expect(repository.deleted, isFalse);
    expect(cubit.state.pendingCaptures[MediaKind.document], captured);
    expect(cubit.state.profile!.nextStep, KycStep.document);
    expect(cubit.state.busy, isFalse);
    expect(cubit.state.operation, KycOperation.none);

    expect(await cubit.retryUpload(MediaKind.document), isTrue);
    expect(repository.observedUploads, 1);
    expect(cubit.state.pendingCaptures, isEmpty);
    expect(cubit.state.reviewMedia[MediaKind.document], captured.bytes);
    expect(cubit.state.profile!.nextStep, KycStep.selfie);
    expect(await cubit.retryUpload(MediaKind.document), isFalse);
    expect(repository.observedUploads, 1);
  });

  test(
    'selfie forwards its mirrored guide and retains cropped bytes for upload',
    () async {
      repository.profile = profile(step: KycStep.selfie);
      final selfie = CapturedMedia(
        kind: MediaKind.selfie,
        filePath: '/private/cropped-selfie.jpg',
        bytes: Uint8List.fromList([7, 8]),
      );
      repository.captureResult = selfie;
      await cubit.load();
      final crop = CameraCaptureCrop.fromViewport(
        viewportWidth: 390,
        viewportHeight: 844,
        frameLeft: 95,
        frameTop: 220,
        frameWidth: 200,
        frameHeight: 200 / .74,
        previewAspectRatio: 9 / 16,
        isPreviewMirrored: true,
      );
      expect(
        await cubit.capture(
          MediaKind.selfie,
          crop: crop,
          uploadImmediately: false,
        ),
        isTrue,
      );
      expect(repository.receivedCrop, same(crop));
      expect(cubit.state.pendingCaptures[MediaKind.selfie], same(selfie));
      expect(repository.observedUploads, 0);
      expect(await cubit.retryUpload(MediaKind.selfie), isTrue);
      expect(repository.observedUploads, 1);
      expect(cubit.state.pendingCaptures, isEmpty);
      expect(cubit.state.reviewMedia[MediaKind.selfie], selfie.bytes);
    },
  );

  test(
    'canceling deferred capture never uploads or changes progress',
    () async {
      await cubit.load();
      repository.captureCancelled = true;

      expect(
        await cubit.capture(MediaKind.document, uploadImmediately: false),
        isFalse,
      );
      expect(repository.observedUploads, 0);
      expect(cubit.state.pendingCaptures, isEmpty);
      expect(cubit.state.profile!.nextStep, KycStep.document);
      expect(cubit.state.busy, isFalse);
      expect(cubit.state.operation, KycOperation.none);
    },
  );

  test('deferred capture drains the refresh queued during capture', () async {
    await cubit.load();
    repository.captureGate = Completer<void>();
    final capture = cubit.capture(MediaKind.document, uploadImmediately: false);
    final refresh = cubit.refresh();
    expect(repository.observedLoads, 1);

    repository.captureGate!.complete();
    expect(await capture, isTrue);
    await refresh;

    expect(repository.observedLoads, 2);
    expect(repository.observedUploads, 0);
    expect(cubit.state.pendingCaptures[MediaKind.document], captured);
    expect(cubit.state.busy, isFalse);
    expect(cubit.state.refreshing, isFalse);
  });

  test('capture completing after flow disposal never uploads', () async {
    await cubit.load();
    repository.captureGate = Completer<void>();
    final capture = cubit.capture(MediaKind.document, uploadImmediately: false);
    await cubit.close();
    repository.captureGate!.complete();

    expect(await capture, isFalse);
    expect(repository.observedUploads, 0);
    expect(cubit.state.pendingCaptures, isEmpty);
  });

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
  int observedLoads = 0;
  int observedUploads = 0;
  bool captureCancelled = false;
  Completer<void>? captureGate;
  CapturedMedia? recovered;
  CapturedMedia captureResult = captured;
  CameraCaptureCrop? receivedCrop;
  @override
  Future<Result<KycProfile>> load() async {
    observedLoads++;
    return loadFailure
        ? const Failure(
            AppFailure(
              code: 'NETWORK_ERROR',
              message: 'Connection interrupted.',
            ),
          )
        : Success(profile);
  }

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
    CameraCaptureCrop? crop,
  }) async {
    captureCount++;
    receivedCrop = crop;
    if (captureGate != null) await captureGate!.future;
    return Success(captureCancelled ? null : captureResult);
  }

  @override
  Future<Result<KycProfile>> upload(
    CapturedMedia media, {
    void Function(int, int)? onProgress,
  }) async {
    observedUploads++;
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
  Future<Result<KycProfile>> verifyIdentity() async => Success(profile);
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
