import '../../../../core/domain/result.dart';
import '../entities/capture_camera.dart';
import '../entities/kyc_profile.dart';

abstract interface class CaptureCameraRepository {
  Future<Result<CaptureCameraSession>> initialize(MediaKind kind);
  Future<Result<CaptureCameraSession>> setFlash(bool enabled);
  Future<Result<void>> close();
}
