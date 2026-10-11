import '../../../../core/domain/result.dart';
import '../entities/capture_camera.dart';
import '../entities/kyc_profile.dart';
import '../repositories/capture_camera_repository.dart';

class InitializeCaptureCamera {
  const InitializeCaptureCamera(this.repository);
  final CaptureCameraRepository repository;
  Future<Result<CaptureCameraSession>> call(MediaKind kind) =>
      repository.initialize(kind);
}

class SetCaptureCameraFlash {
  const SetCaptureCameraFlash(this.repository);
  final CaptureCameraRepository repository;
  Future<Result<CaptureCameraSession>> call(bool enabled) =>
      repository.setFlash(enabled);
}

class CloseCaptureCamera {
  const CloseCaptureCamera(this.repository);
  final CaptureCameraRepository repository;
  Future<Result<void>> call() => repository.close();
}
