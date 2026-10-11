import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/core/domain/result.dart';
import 'package:kyc_onboarding/features/kyc/data/datasources/camera_datasource.dart';
import 'package:kyc_onboarding/features/kyc/data/datasources/in_app_camera_driver.dart';
import 'package:kyc_onboarding/features/kyc/data/repositories/capture_camera_repository_impl.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';
import 'package:kyc_onboarding/features/kyc/domain/usecases/capture_camera_usecases.dart';
import 'package:kyc_onboarding/features/kyc/presentation/bloc/capture_camera_cubit.dart';

const rear = CameraDescription(
  name: 'rear',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);
const front = CameraDescription(
  name: 'front',
  lensDirection: CameraLensDirection.front,
  sensorOrientation: 270,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'document uses rear and selfie uses front with audio disabled',
    () async {
      final controllers = <TestCameraController>[];
      final driver = InAppCameraDriver(
        cameras: () async => [front, rear],
        controller: (description, resolution, {required enableAudio}) {
          expect(resolution, ResolutionPreset.veryHigh);
          expect(enableAudio, isFalse);
          final camera = TestCameraController(description);
          controllers.add(camera);
          return camera;
        },
      );
      final document = await driver.initialize(MediaKind.document);
      expect(controllers.single.description, rear);
      expect(document.aspectRatio, .75);
      expect(document.canToggleFlash, isTrue);
      expect(controllers.single.flashModes, [FlashMode.off]);
      expect(controllers.single.orientation, DeviceOrientation.portraitUp);
      await driver.setFlash(true);
      expect(controllers.single.flashModes.last, FlashMode.torch);
      final selfie = await driver.initialize(MediaKind.selfie);
      expect(controllers.first.disposed, isTrue);
      expect(controllers.last.description, front);
      expect(selfie.canToggleFlash, isFalse);
      expect(selfie.flashEnabled, isFalse);
      await expectLater(
        driver.setFlash(true),
        throwsA(isA<CameraCaptureException>()),
      );
      await driver.close();
      expect(controllers.last.disposed, isTrue);
    },
  );

  test(
    'missing required lens fails instead of using the opposite camera',
    () async {
      var created = 0;
      final driver = InAppCameraDriver(
        cameras: () async => [rear],
        controller: (description, resolution, {required enableAudio}) {
          created++;
          return TestCameraController(description);
        },
      );
      await expectLater(
        driver.initialize(MediaKind.selfie),
        throwsA(
          isA<CameraCaptureException>().having(
            (e) => e.code,
            'code',
            'CAMERA_UNAVAILABLE',
          ),
        ),
      );
      expect(created, 0);
      await driver.close();
    },
  );

  test(
    'repository maps platform permission failures and disposes failed camera',
    () async {
      final camera = TestCameraController(rear)
        ..initializationError = CameraException('CameraAccessDenied', 'denied');
      final driver = InAppCameraDriver(
        cameras: () async => [rear],
        controller: (description, resolution, {required enableAudio}) => camera,
      );

      final repository = CaptureCameraRepositoryImpl(driver);
      final result = await repository.initialize(MediaKind.document);
      expect((result as Failure).error.code, 'CAMERA_PERMISSION');
      expect(camera.disposed, isTrue);
      await driver.close();
    },
  );

  test(
    'camera without flash remains usable and hides the light control',
    () async {
      final camera = TestCameraController(rear)
        ..flashError = CameraException(
          'setFlashModeFailed',
          'No flash hardware',
        );
      final driver = InAppCameraDriver(
        cameras: () async => [rear],
        controller: (description, resolution, {required enableAudio}) => camera,
      );
      final session = await driver.initialize(MediaKind.document);
      expect(session.canToggleFlash, isFalse);
      expect(session.flashEnabled, isFalse);
      await driver.takePicture(MediaKind.document);
      expect(camera.pictures, 1);
      await driver.close();
    },
  );

  test('close waits for initialization and leaves no active camera', () async {
    final gate = Completer<void>();
    final camera = TestCameraController(rear)..initializationGate = gate.future;
    final driver = InAppCameraDriver(
      cameras: () async => [rear],
      controller: (description, resolution, {required enableAudio}) => camera,
    );
    final initializing = driver.initialize(MediaKind.document);
    await Future<void>.delayed(Duration.zero);
    final closing = driver.close();
    gate.complete();
    await initializing;
    await closing;
    expect(camera.disposed, isTrue);
    await expectLater(
      driver.takePicture(MediaKind.document),
      throwsA(isA<CameraCaptureException>()),
    );
    await driver.close();
  });

  test(
    'permission prompt pause and resume dispose the old camera and restore preview',
    () async {
      final permissionPrompt = Completer<void>();
      final controllers = <TestCameraController>[];
      final driver = InAppCameraDriver(
        cameras: () async => [rear],
        controller: (description, resolution, {required enableAudio}) {
          final camera = TestCameraController(description);
          if (controllers.isEmpty) {
            camera.initializationGate = permissionPrompt.future;
          }
          controllers.add(camera);
          return camera;
        },
      );
      final repository = CaptureCameraRepositoryImpl(driver);
      final cubit = CaptureCameraCubit(
        initializeCamera: InitializeCaptureCamera(repository),
        setFlash: SetCaptureCameraFlash(repository),
        closeCamera: CloseCaptureCamera(repository),
      );
      final states = <CaptureCameraStatus>[];
      final subscription = cubit.stream.listen(
        (state) => states.add(state.status),
      );
      final initializing = cubit.initialize(MediaKind.document);
      await Future<void>.delayed(Duration.zero);
      final pausing = cubit.pause();
      final resuming = cubit.resume();
      permissionPrompt.complete();
      await Future.wait([initializing, pausing, resuming]);
      await Future<void>.delayed(Duration.zero);
      expect(controllers.length, 2);
      expect(controllers.first.disposed, isTrue);
      expect(controllers.last.disposed, isFalse);
      expect(cubit.state.isReady, isTrue);
      expect(states, [
        CaptureCameraStatus.initializing,
        CaptureCameraStatus.paused,
        CaptureCameraStatus.initializing,
        CaptureCameraStatus.ready,
      ]);
      await cubit.close();
      expect(controllers.last.disposed, isTrue);
      await subscription.cancel();
    },
  );

  test(
    'capture cannot use a camera initialized for the other media kind',
    () async {
      final camera = TestCameraController(front);
      final driver = InAppCameraDriver(
        cameras: () async => [front],
        controller: (description, resolution, {required enableAudio}) => camera,
      );
      await driver.initialize(MediaKind.selfie);
      await expectLater(
        driver.takePicture(MediaKind.document),
        throwsA(isA<CameraCaptureException>()),
      );
      expect(camera.pictures, 0);
      await driver.close();
    },
  );

  test(
    'in-app capture persists private files with recoverable IDs and chosen type',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'in_app_camera_test_',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final source = File('${temporary.path}/source.jpg');
      await source.writeAsBytes([1, 2, 3]);
      final driver = PictureDriver(XFile(source.path));
      final datasource = InAppCameraDataSource(
        driver: driver,
        directory: () async => temporary,
      );
      final captured = await datasource.capture(
        MediaKind.document,
        'profile_a',
        documentType: DocumentType.nationalId,
      );
      expect(driver.kind, MediaKind.document);
      expect(captured!.captureId, matches(r'^[a-f0-9]{32}$'));
      expect(captured.documentType, DocumentType.nationalId);
      expect(captured.filePath, contains('/kyc_captures/profile_a/'));
      expect(await source.exists(), isFalse);
      final recovered = await datasource.recover(
        MediaKind.document,
        'profile_a',
      );
      expect(recovered!.captureId, captured.captureId);
      expect(await datasource.recover(MediaKind.document, 'profile_b'), isNull);
      await datasource.remove(captured);
      expect(await datasource.recover(MediaKind.document, 'profile_a'), isNull);
    },
  );
}

class TestCameraController extends CameraController {
  TestCameraController(CameraDescription description)
    : super(description, ResolutionPreset.high, enableAudio: false);
  CameraException? initializationError;
  CameraException? flashError;
  Future<void>? initializationGate;
  final flashModes = <FlashMode>[];
  DeviceOrientation? orientation;
  bool disposed = false;
  int pictures = 0;
  @override
  Future<void> initialize() async {
    if (initializationGate != null) await initializationGate;
    if (initializationError != null) throw initializationError!;
    value = value.copyWith(
      isInitialized: true,
      previewSize: const Size(400, 300),
    );
  }

  @override
  Future<void> setFlashMode(FlashMode mode) async {
    if (flashError != null) throw flashError!;
    flashModes.add(mode);
    value = value.copyWith(flashMode: mode);
  }

  @override
  Future<void> lockCaptureOrientation([DeviceOrientation? orientation]) async {
    this.orientation = orientation;
    value = value.copyWith(lockedCaptureOrientation: Optional.of(orientation!));
  }

  @override
  Future<XFile> takePicture() async {
    pictures++;
    return XFile('/private/capture.jpg');
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await super.dispose();
  }
}

class PictureDriver extends InAppCameraDriver {
  PictureDriver(this.file);
  final XFile file;
  MediaKind? kind;
  @override
  Future<XFile> takePicture(MediaKind kind) async {
    this.kind = kind;
    return file;
  }
}
