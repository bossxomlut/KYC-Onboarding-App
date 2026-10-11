import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/core/domain/result.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/capture_camera.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';
import 'package:kyc_onboarding/features/kyc/domain/repositories/capture_camera_repository.dart';
import 'package:kyc_onboarding/features/kyc/domain/usecases/capture_camera_usecases.dart';
import 'package:kyc_onboarding/features/kyc/presentation/bloc/capture_camera_cubit.dart';

CaptureCameraCubit makeCubit(TestCameraRepository repository) =>
    CaptureCameraCubit(
      initializeCamera: InitializeCaptureCamera(repository),
      setFlash: SetCaptureCameraFlash(repository),
      closeCamera: CloseCaptureCamera(repository),
    );

void main() {
  test(
    'ready session is page scoped and pause/resume reopens the same lens',
    () async {
      final repository = TestCameraRepository();
      final cubit = makeCubit(repository);
      await cubit.initialize(MediaKind.document);
      expect(cubit.state.isReady, isTrue);
      expect(cubit.state.session!.kind, MediaKind.document);
      await cubit.toggleFlash();
      expect(cubit.state.session!.flashEnabled, isTrue);
      await cubit.pause();
      expect(cubit.state.status, CaptureCameraStatus.paused);
      expect(cubit.state.session, isNull);
      expect(repository.closes, 1);
      await cubit.resume();
      expect(repository.kinds, [MediaKind.document, MediaKind.document]);
      expect(cubit.state.session!.flashEnabled, isFalse);
      await cubit.close();
      expect(repository.closes, 2);
    },
  );

  test('pause during initialization ignores late ready state', () async {
    final repository = TestCameraRepository()..pending = Completer();
    final cubit = makeCubit(repository);
    final initializing = cubit.initialize(MediaKind.selfie);
    await cubit.pause();
    repository.pending!.complete(
      const Success(
        CaptureCameraSession(kind: MediaKind.selfie, aspectRatio: .75),
      ),
    );
    await initializing;
    expect(cubit.state.status, CaptureCameraStatus.paused);
    expect(cubit.state.session, isNull);
    await cubit.close();
  });

  test(
    'close is idempotent and late initialization cannot emit after disposal',
    () async {
      final repository = TestCameraRepository()..pending = Completer();
      final cubit = makeCubit(repository);
      final initializing = cubit.initialize(MediaKind.document);
      await Future.wait([cubit.close(), cubit.close()]);
      repository.pending!.complete(
        const Success(
          CaptureCameraSession(kind: MediaKind.document, aspectRatio: .75),
        ),
      );
      await initializing;
      expect(cubit.isClosed, isTrue);
      expect(repository.closes, 1);
    },
  );

  test(
    'permission failure renders retry and retry initializes the requested kind',
    () async {
      final repository = TestCameraRepository()
        ..failure = const AppFailure(
          code: 'CAMERA_PERMISSION',
          message: 'Allow camera access.',
        );
      final cubit = makeCubit(repository);
      await cubit.initialize(MediaKind.document);
      expect(cubit.state.status, CaptureCameraStatus.failure);
      expect(cubit.state.failure!.code, 'CAMERA_PERMISSION');
      repository.failure = null;
      await cubit.initialize(MediaKind.document);
      expect(cubit.state.isReady, isTrue);
      await cubit.close();
    },
  );

  test('selfie never exposes or invokes flash', () async {
    final repository = TestCameraRepository();
    final cubit = makeCubit(repository);
    await cubit.initialize(MediaKind.selfie);
    await cubit.toggleFlash();
    expect(repository.flashCalls, 0);
    await cubit.close();
  });

  test('concurrent pause and close await the same hardware release', () async {
    final repository = TestCameraRepository()..closeGate = Completer<void>();
    final cubit = makeCubit(repository);
    await cubit.initialize(MediaKind.document);
    var pausedAgain = false;
    var closed = false;
    final pause = cubit.pause();
    final repeated = cubit.pause().then((_) => pausedAgain = true);
    final close = cubit.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(pausedAgain, isFalse);
    expect(closed, isFalse);
    expect(repository.closes, 1);
    repository.closeGate!.complete();
    await Future.wait([pause, repeated, close]);
    expect(cubit.isClosed, isTrue);
  });
}

class TestCameraRepository implements CaptureCameraRepository {
  final kinds = <MediaKind>[];
  int closes = 0;
  int flashCalls = 0;
  Completer<Result<CaptureCameraSession>>? pending;
  Completer<void>? closeGate;
  AppFailure? failure;
  CaptureCameraSession? session;
  @override
  Future<Result<CaptureCameraSession>> initialize(MediaKind kind) async {
    kinds.add(kind);
    if (pending != null) return pending!.future;
    if (failure != null) return Failure(failure!);
    session = CaptureCameraSession(
      kind: kind,
      aspectRatio: .75,
      canToggleFlash: kind == MediaKind.document,
    );
    return Success(session!);
  }

  @override
  Future<Result<CaptureCameraSession>> setFlash(bool enabled) async {
    flashCalls++;
    session = CaptureCameraSession(
      kind: session!.kind,
      aspectRatio: .75,
      canToggleFlash: true,
      flashEnabled: enabled,
    );
    return Success(session!);
  }

  @override
  Future<Result<void>> close() async {
    closes++;
    if (closeGate != null) await closeGate!.future;
    return const Success(null);
  }
}
