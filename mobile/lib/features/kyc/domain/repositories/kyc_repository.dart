import 'dart:typed_data';
import '../../../../core/domain/result.dart';
import '../entities/kyc_profile.dart';

abstract interface class KycRepository {
  Future<Result<KycProfile>> load();
  Future<Result<KycProfile>> saveDetails(PersonalDetails details);
  Future<Result<CapturedMedia?>> capture(
    MediaKind kind,
    String profileId, {
    DocumentType? documentType,
  });
  Future<Result<CapturedMedia?>> recover(
    MediaKind kind,
    String profileId, {
    String? confirmedCaptureId,
  });
  Future<Result<KycProfile>> upload(
    CapturedMedia media, {
    void Function(int, int)? onProgress,
  });
  Future<Result<Uint8List>> privateMedia(MediaKind kind);
  Future<Result<KycProfile>> submit();
  Future<Result<KycProfile>> resubmit();
  Future<Result<void>> discardLocal(String profileId);
}
