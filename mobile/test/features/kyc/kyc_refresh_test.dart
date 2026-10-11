import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/core/domain/result.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';
import 'package:kyc_onboarding/features/kyc/domain/usecases/kyc_usecases.dart';
import 'package:kyc_onboarding/features/kyc/presentation/bloc/kyc_cubit.dart';

import 'kyc_cubit_test.dart' show FakeKycRepository;

void main() {
  late RefreshRepository repository;
  late KycCubit cubit;
  setUp(() {
    repository = RefreshRepository();
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
    'profile reload requested during photo IO runs once afterward',
    () async {
      await cubit.load();
      repository.mediaGate = Completer<void>();
      final photos = cubit.loadReviewMedia();
      repository.profile = mediaProfile(status: KycStatus.verified);
      final firstReload = cubit.load();
      final secondReload = cubit.load();
      expect(repository.loadCalls, 1);
      repository.mediaGate!.complete();
      await Future.wait([photos, firstReload, secondReload]);
      expect(repository.loadCalls, 2);
      expect(cubit.state.profile!.status, KycStatus.verified);
    },
  );

  test(
    'profile reload replaces cached bytes when server media changes',
    () async {
      await cubit.load();
      await cubit.loadReviewMedia();
      expect(cubit.state.reviewMedia[MediaKind.document], [1]);
      repository.profile = mediaProfile(documentId: 'replacement-document');
      repository.documentBytes = Uint8List.fromList([2]);
      await cubit.load();
      expect(cubit.state.profile!.document!.id, 'replacement-document');
      expect(cubit.state.reviewMedia[MediaKind.document], [2]);
      expect(repository.mediaCalls, [MediaKind.document, MediaKind.document]);
    },
  );

  test('closing during photo IO discards a queued profile reload', () async {
    await cubit.load();
    repository.mediaGate = Completer<void>();
    final photos = cubit.loadReviewMedia();
    final reload = cubit.load();
    await cubit.close();
    repository.mediaGate!.complete();
    await Future.wait([photos, reload]);
    expect(repository.loadCalls, 1);
  });

  test(
    'silent refresh keeps existing content interactive and merges GETs',
    () async {
      await cubit.load();
      repository.loadGate = Completer<void>();
      final first = cubit.refresh();
      final second = cubit.refresh();
      expect(cubit.state.refreshing, isTrue);
      expect(cubit.state.busy, isFalse);
      expect(cubit.state.operation, KycOperation.none);
      expect(cubit.state.profile, isNotNull);
      repository.loadGate!.complete();
      await Future.wait([first, second]);
      expect(repository.loadCalls, 2);
      expect(cubit.state.refreshing, isFalse);
    },
  );

  test(
    'queued refresh reconciles uncertain submit without repeating POST',
    () async {
      repository.profile = const KycProfile(
        id: 'profile',
        status: KycStatus.inProgress,
        nextStep: KycStep.review,
        personalDetails: PersonalDetails(
          fullName: 'Demo User',
          dateOfBirth: '1995-04-15',
          nationality: 'Vietnamese',
          address: '1 Demo Street',
          documentNumber: 'DEMO1234',
        ),
        document: KycMedia(id: 'document', mimeType: 'image/png', size: 1),
        selfie: KycMedia(id: 'selfie', mimeType: 'image/png', size: 1),
      );
      await cubit.load();
      repository.submitGate = Completer<void>();
      final submission = cubit.submit();
      expect(cubit.state.operation, KycOperation.submitting);
      final first = cubit.refresh();
      final second = cubit.refresh();
      repository.profile = mediaProfile();
      repository.submitGate!.complete();
      expect(await submission, isFalse);
      await Future.wait([first, second]);
      expect(repository.submitCalls, 1);
      expect(repository.loadCalls, 2);
      expect(cubit.state.profile!.status, KycStatus.pendingReview);
      expect(cubit.state.error, isNull);
    },
  );

  test('acknowledged upload preserves its photo preview', () async {
    repository.profile = const KycProfile(
      id: 'profile',
      status: KycStatus.inProgress,
      nextStep: KycStep.document,
    );
    repository.uploadFailure = true;
    await cubit.load();
    await cubit.capture(MediaKind.document);
    expect(cubit.state.pendingCaptures, isNotEmpty);
    repository.profile = const KycProfile(
      id: 'profile',
      status: KycStatus.inProgress,
      nextStep: KycStep.selfie,
      document: KycMedia(
        id: 'accepted-document',
        mimeType: 'image/png',
        size: 1,
        captureId: 'capture-id',
      ),
    );
    await cubit.refresh();
    expect(cubit.state.pendingCaptures, isEmpty);
    expect(cubit.state.reviewMedia[MediaKind.document], [3]);
    expect(cubit.state.error, isNull);
    expect(repository.captureCount, 1);
  });

  test(
    'visible summary loads newly added media without an existing cache',
    () async {
      repository.profile = const KycProfile(
        id: 'profile',
        status: KycStatus.pendingReview,
        nextStep: KycStep.result,
      );
      await cubit.load();
      cubit.retainReviewMediaView();
      await cubit.loadReviewMedia();
      repository.profile = mediaProfile();
      await cubit.refresh();
      expect(cubit.state.reviewMedia[MediaKind.document], [1]);
      expect(repository.mediaCalls, [MediaKind.document]);
      cubit.releaseReviewMediaView();
    },
  );

  test('resume replaces a GET snapshot captured before background', () async {
    await cubit.load();
    repository.loadGate = Completer<void>();
    final oldRefresh = cubit.refresh();
    cubit.prepareForResume();
    repository.profile = mediaProfile(status: KycStatus.rejected);
    final resume = cubit.refresh();
    repository.loadGate!.complete();
    await Future.wait([oldRefresh, resume]);
    expect(cubit.state.profile!.status, KycStatus.rejected);
    expect(repository.loadCalls, 3);
  });

  test(
    'resume restores a visible photo whose earlier GET was invalidated',
    () async {
      await cubit.load();
      cubit.retainReviewMediaView();
      await cubit.loadReviewMedia();
      repository.profile = mediaProfile(documentId: 'replacement-document');
      repository.documentBytes = Uint8List.fromList([2]);
      repository.mediaGate = Completer<void>();
      final oldRefresh = cubit.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.profile!.document!.id, 'replacement-document');
      expect(cubit.state.reviewMedia, isEmpty);
      cubit.prepareForResume();
      final resume = cubit.refresh();
      repository.mediaGate!.complete();
      await Future.wait([oldRefresh, resume]);
      expect(cubit.state.reviewMedia[MediaKind.document], [2]);
      expect(repository.mediaCalls, [
        MediaKind.document,
        MediaKind.document,
        MediaKind.document,
      ]);
      cubit.releaseReviewMediaView();
    },
  );

  test(
    'queued save waits for the fresh resume GET before checking editability',
    () async {
      repository.profile = mediaProfile(status: KycStatus.inProgress);
      await cubit.load();
      final oldGate = Completer<void>();
      repository.loadGate = oldGate;
      final oldRefresh = cubit.refresh();
      cubit.prepareForResume();
      repository.profile = mediaProfile(status: KycStatus.rejected);
      final freshGate = Completer<void>();
      repository.loadGate = freshGate;
      final resume = cubit.refresh();
      final saving = cubit.saveDetails(
        const PersonalDetails(
          fullName: 'Demo User',
          dateOfBirth: '1995-04-15',
          nationality: 'Vietnamese',
          address: '1 Demo Street',
          documentNumber: 'DEMO1234',
        ),
      );
      oldGate.complete();
      await Future<void>.delayed(Duration.zero);
      final attemptedWhileWaiting = repository.saved;
      freshGate.complete();
      final saved = await saving;
      await Future.wait([oldRefresh, resume]);
      expect(attemptedWhileWaiting, isFalse);
      expect(saved, isFalse);
      expect(repository.saved, isFalse);
      expect(cubit.state.profile!.status, KycStatus.rejected);
    },
  );
}

KycProfile mediaProfile({
  KycStatus status = KycStatus.pendingReview,
  String documentId = 'document',
}) => KycProfile(
  id: 'profile',
  status: status,
  nextStep: KycStep.result,
  document: KycMedia(id: documentId, mimeType: 'image/png', size: 1),
);

class RefreshRepository extends FakeKycRepository {
  RefreshRepository() {
    profile = mediaProfile();
  }
  int loadCalls = 0;
  final mediaCalls = <MediaKind>[];
  Uint8List documentBytes = Uint8List.fromList([1]);
  Completer<void>? mediaGate;
  Completer<void>? loadGate;
  Completer<void>? submitGate;
  int submitCalls = 0;
  @override
  Future<Result<KycProfile>> load() async {
    loadCalls++;
    final snapshot = super.load();
    if (loadGate != null) await loadGate!.future;
    return snapshot;
  }

  @override
  Future<Result<Uint8List>> privateMedia(MediaKind kind) async {
    mediaCalls.add(kind);
    if (mediaGate != null) await mediaGate!.future;
    return Success(documentBytes);
  }

  @override
  Future<Result<KycProfile>> submit() async {
    submitCalls++;
    if (submitGate != null) await submitGate!.future;
    return const Failure(
      AppFailure(code: 'NETWORK_ERROR', message: 'Response interrupted.'),
    );
  }

  @override
  Future<Result<CapturedMedia?>> capture(
    MediaKind kind,
    String profileId, {
    DocumentType? documentType,
  }) async {
    captureCount++;
    return Success(
      CapturedMedia(
        kind: kind,
        filePath: '/private/capture.png',
        bytes: Uint8List.fromList([3]),
        captureId: 'capture-id',
      ),
    );
  }
}
