import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import '../../domain/entities/capture_camera.dart';
import '../../domain/entities/kyc_profile.dart';
import 'camera_capture_exception.dart';

typedef CaptureCameraControllerFactory =
    CameraController Function(
      CameraDescription description,
      ResolutionPreset resolution, {
      required bool enableAudio,
    });

/// Owns the plugin and serializes all hardware operations, including disposal.
class InAppCameraDriver {
  InAppCameraDriver({
    Future<List<CameraDescription>> Function()? cameras,
    CaptureCameraControllerFactory? controller,
  }) : _cameras = cameras ?? availableCameras,
       _controllerFactory = controller ?? _createController;

  final Future<List<CameraDescription>> Function() _cameras;
  final CaptureCameraControllerFactory _controllerFactory;
  CameraController? _controller;
  CaptureCameraSession? _session;
  Future<void> _operations = Future.value();

  static CameraController _createController(
    CameraDescription description,
    ResolutionPreset resolution, {
    required bool enableAudio,
  }) => CameraController(description, resolution, enableAudio: enableAudio);

  Future<T> _run<T>(Future<T> Function() operation) {
    final next = _operations.then((_) async {
      try {
        return await operation();
      } on CameraCaptureException {
        rethrow;
      } on CameraException catch (error) {
        throw _mapCameraException(error.code);
      } on PlatformException catch (error) {
        throw _mapCameraException(error.code);
      } catch (_) {
        throw const CameraCaptureException(
          'CAMERA_UNAVAILABLE',
          'The camera is unavailable. Please try again on a device with a camera.',
        );
      }
    });
    // A failed operation must not poison subsequent Retry / close operations.
    _operations = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<CaptureCameraSession> initialize(MediaKind kind) => _run(() async {
    await _disposeController();
    final requiredLens = kind == MediaKind.selfie
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    final matching = (await _cameras()).where(
      (camera) => camera.lensDirection == requiredLens,
    );
    if (matching.isEmpty) {
      throw CameraCaptureException(
        'CAMERA_UNAVAILABLE',
        kind == MediaKind.selfie
            ? 'A front camera is required to take your selfie. Please use a device with a front camera.'
            : 'A rear camera is required to photograph your document. Please use a device with a rear camera.',
      );
    }
    final controller = _controllerFactory(
      matching.first,
      ResolutionPreset.veryHigh,
      enableAudio: false,
    );
    _controller = controller;
    try {
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      var flashSupported = kind == MediaKind.document;
      try {
        await controller.setFlashMode(FlashMode.off);
      } on CameraException catch (error) {
        if (_mapCameraException(error.code).code == 'CAMERA_PERMISSION') {
          rethrow;
        }
        // Cameras without a light must still allow document/selfie capture.
        flashSupported = false;
      }
      _session = CaptureCameraSession(
        kind: kind,
        aspectRatio: 1 / controller.value.aspectRatio,
        canToggleFlash: flashSupported,
        isPreviewMirrored: requiredLens == CameraLensDirection.front,
      );
      return _session!;
    } catch (_) {
      await _disposeController();
      rethrow;
    }
  });

  Future<CaptureCameraSession> setFlash(bool enabled) => _run(() async {
    final controller = _controller;
    final session = _session;
    if (controller == null ||
        session == null ||
        !controller.value.isInitialized) {
      throw const CameraCaptureException(
        'CAMERA_UNAVAILABLE',
        'The camera is not ready. Please try again.',
      );
    }
    if (enabled && !session.canToggleFlash) {
      throw const CameraCaptureException(
        'CAMERA_FLASH_UNAVAILABLE',
        'Flash is unavailable for the front camera.',
      );
    }
    try {
      await controller.setFlashMode(enabled ? FlashMode.torch : FlashMode.off);
    } on CameraException {
      throw const CameraCaptureException(
        'CAMERA_FLASH_UNAVAILABLE',
        'This camera does not support the light. Please use a well-lit area.',
      );
    }
    _session = CaptureCameraSession(
      kind: session.kind,
      aspectRatio: session.aspectRatio,
      flashEnabled: enabled,
      canToggleFlash: session.canToggleFlash,
      isPreviewMirrored: session.isPreviewMirrored,
    );
    return _session!;
  });

  Future<XFile> takePicture(MediaKind kind) => _run(() async {
    final controller = _controller;
    if (controller == null ||
        _session?.kind != kind ||
        !controller.value.isInitialized) {
      throw const CameraCaptureException(
        'CAMERA_UNAVAILABLE',
        'The requested camera is not ready. Please reopen the camera and try again.',
      );
    }
    return controller.takePicture();
  });

  Future<void> close() => _run(_disposeController);

  Future<void> _disposeController() async {
    final controller = _controller;
    _controller = null;
    _session = null;
    if (controller != null) await controller.dispose();
  }

  /// The app passes this as a WidgetBuilder; presentation never sees the SDK.
  Widget buildPreview(BuildContext context) {
    final controller = _controller;
    return controller != null && controller.value.isInitialized
        ? CameraPreview(controller)
        : const SizedBox.expand();
  }

  CameraCaptureException _mapCameraException(String code) {
    final normalized = code.toLowerCase();
    if (normalized.contains('access') || normalized.contains('permission')) {
      return const CameraCaptureException(
        'CAMERA_PERMISSION',
        'Allow camera access in your device Settings, then return here and retry.',
      );
    }
    return const CameraCaptureException(
      'CAMERA_UNAVAILABLE',
      'The camera is unavailable. Please try again on a device with a camera.',
    );
  }
}
