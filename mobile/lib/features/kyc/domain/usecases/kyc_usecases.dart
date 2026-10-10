import 'dart:typed_data';
import '../../../../core/domain/result.dart';
import '../entities/kyc_profile.dart';
import '../repositories/kyc_repository.dart';

class LoadKyc {
  const LoadKyc(this.repository);
  final KycRepository repository;
  Future<Result<KycProfile>> call() => repository.load();
}

class SavePersonalDetails {
  SavePersonalDetails(this.repository, {DateTime Function()? now})
      : _now = now ?? DateTime.now;
  final KycRepository repository;
  final DateTime Function() _now;
  Future<Result<KycProfile>> call(PersonalDetails details) {
    final errors = details.validate(_now());
    if (errors.isNotEmpty) {
      return Future.value(
        Failure(AppFailure(code: 'VALIDATION', message: errors.values.first)),
      );
    }
    return repository.saveDetails(details);
  }
}

class CaptureMedia {
  const CaptureMedia(this.repository);
  final KycRepository repository;
  Future<Result<CapturedMedia?>> call(
    MediaKind kind,
    String profileId, {
    DocumentType? documentType,
  }) =>
      repository.capture(kind, profileId, documentType: documentType);
}

class RecoverCapture {
  const RecoverCapture(this.repository);
  final KycRepository repository;
  Future<Result<CapturedMedia?>> call(
    MediaKind kind,
    String profileId, {
    String? confirmedCaptureId,
  }) =>
      repository.recover(
        kind,
        profileId,
        confirmedCaptureId: confirmedCaptureId,
      );
}

class UploadMedia {
  const UploadMedia(this.repository);
  final KycRepository repository;
  Future<Result<KycProfile>> call(
    CapturedMedia media, {
    void Function(int, int)? onProgress,
  }) =>
      repository.upload(media, onProgress: onProgress);
}

class LoadPrivateMedia {
  const LoadPrivateMedia(this.repository);
  final KycRepository repository;
  Future<Result<Uint8List>> call(MediaKind kind) =>
      repository.privateMedia(kind);
}

class SubmitKyc {
  const SubmitKyc(this.repository);
  final KycRepository repository;
  Future<Result<KycProfile>> call() => repository.submit();
}

class ResubmitKyc {
  const ResubmitKyc(this.repository);
  final KycRepository repository;
  Future<Result<KycProfile>> call() => repository.resubmit();
}

class DiscardLocalMedia {
  const DiscardLocalMedia(this.repository);
  final KycRepository repository;
  Future<Result<void>> call(String profileId) =>
      repository.discardLocal(profileId);
}
