import '../../../../core/domain/result.dart';
import '../../domain/entities/capture_camera.dart';
import '../../domain/entities/kyc_profile.dart';
import '../../domain/repositories/capture_camera_repository.dart';
import '../datasources/camera_capture_exception.dart';
import '../datasources/in_app_camera_driver.dart';

class CaptureCameraRepositoryImpl implements CaptureCameraRepository {
  const CaptureCameraRepositoryImpl(this.driver);
  final InAppCameraDriver driver;

  Future<Result<T>> _guard<T>(Future<T> Function() operation) async {
    try {
      return Success(await operation());
    } on CameraCaptureException catch (error) {
      return Failure(AppFailure(code: error.code, message: error.message));
    } catch (_) {
      return const Failure(
        AppFailure(
          code: 'CAMERA_UNAVAILABLE',
          message: 'The camera is unavailable. Please try again.',
        ),
      );
    }
  }

  @override
  Future<Result<CaptureCameraSession>> initialize(MediaKind kind) =>
      _guard(() => driver.initialize(kind));
  @override
  Future<Result<CaptureCameraSession>> setFlash(bool enabled) =>
      _guard(() => driver.setFlash(enabled));
  @override
  Future<Result<void>> close() => _guard(driver.close);
}
