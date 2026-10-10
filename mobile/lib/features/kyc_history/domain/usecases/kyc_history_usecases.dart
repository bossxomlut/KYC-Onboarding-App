import 'dart:typed_data';
import '../../../../core/domain/result.dart';
import '../../../kyc/domain/entities/kyc_profile.dart';
import '../entities/kyc_history.dart';
import '../repositories/kyc_history_repository.dart';

class LoadKycHistory {
  const LoadKycHistory(this._repository);
  final KycHistoryRepository _repository;
  Future<Result<KycHistoryPageResult>> call({
    int offset = 0,
    String? reviewerUserId,
  }) => _repository.load(offset: offset, reviewerUserId: reviewerUserId);
}

class LoadKycHistoryMedia {
  const LoadKycHistoryMedia(this._repository);
  final KycHistoryRepository _repository;
  Future<Result<Uint8List>> call(
    String submissionId,
    MediaKind kind, {
    String? reviewerUserId,
  }) => _repository.media(submissionId, kind, reviewerUserId: reviewerUserId);
}
