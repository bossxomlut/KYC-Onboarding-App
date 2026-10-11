import 'dart:typed_data';
import '../../../../core/domain/result.dart';
import '../../../../core/network/api_failure.dart';
import '../../domain/entities/kyc_profile.dart';
import '../../domain/repositories/kyc_repository.dart';
import '../datasources/camera_datasource.dart';
import '../datasources/kyc_remote_datasource.dart';

class KycRepositoryImpl implements KycRepository {
  const KycRepositoryImpl(this.remote, this.camera);
  final KycRemoteDataSource remote;
  final CameraDataSource camera;

  Future<Result<T>> _guard<T>(Future<T> Function() operation) async {
    try {
      return Success(await operation());
    } on CameraCaptureException catch (e) {
      return Failure(AppFailure(code: e.code, message: e.message));
    } catch (e) {
      return Failure(mapApiFailure(e));
    }
  }

  @override
  Future<Result<KycProfile>> load() => _guard(remote.load);
  @override
  Future<Result<KycProfile>> saveDetails(PersonalDetails details) =>
      _guard(() => remote.saveDetails(details));
  @override
  Future<Result<CapturedMedia?>> capture(
    MediaKind kind,
    String profileId, {
    DocumentType? documentType,
  }) =>
      _guard(() => camera.capture(kind, profileId, documentType: documentType));
  @override
  Future<Result<CapturedMedia?>> recover(
    MediaKind kind,
    String profileId, {
    String? confirmedCaptureId,
  }) => _guard(() async {
    final media = await camera.recover(kind, profileId);
    if (media != null &&
        media.captureId != null &&
        media.captureId == confirmedCaptureId) {
      // Server accepted this exact upload before process termination; do not block submission with a stale draft.
      await camera.remove(media);
      return null;
    }
    return media;
  });
  @override
  Future<Result<KycProfile>> upload(
    CapturedMedia media, {
    void Function(int, int)? onProgress,
  }) => _guard(() async {
    final profile = await remote.upload(media, onProgress: onProgress);
    await camera.remove(media);
    return profile;
  });
  @override
  Future<Result<Uint8List>> privateMedia(MediaKind kind) =>
      _guard(() => remote.privateMedia(kind));
  @override
  Future<Result<KycProfile>> submit() => _guard(remote.submit);
  @override
  Future<Result<KycProfile>> resubmit() => _guard(remote.resubmit);
  @override
  Future<Result<KycProfile>> verifyIdentity() => _guard(remote.verifyIdentity);
  @override
  Future<Result<void>> discardLocal(String profileId) =>
      _guard(() => camera.discard(profileId));
}
