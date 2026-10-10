import 'dart:typed_data';
import '../../../../core/domain/result.dart';
import '../../../../core/network/api_failure.dart';
import '../../../kyc/domain/entities/kyc_profile.dart';
import '../../domain/entities/kyc_history.dart';
import '../../domain/repositories/kyc_history_repository.dart';
import '../datasources/kyc_history_remote_datasource.dart';
import '../models/kyc_history_model.dart';

class KycHistoryRepositoryImpl implements KycHistoryRepository {
  const KycHistoryRepositoryImpl(this._remote);
  final KycHistoryRemoteDataSource _remote;
  Future<Result<T>> _guard<T>(Future<T> Function() operation) async {
    try {
      return Success(await operation());
    } catch (error) {
      return Failure(mapApiFailure(error));
    }
  }

  @override
  Future<Result<KycHistoryPageResult>> load({
    int offset = 0,
    int limit = 20,
    String? reviewerUserId,
  }) => _guard(
    () async => KycHistoryModel.page(
      await _remote.load(
        offset: offset,
        limit: limit,
        reviewerUserId: reviewerUserId,
      ),
      offset: offset,
    ),
  );
  @override
  Future<Result<Uint8List>> media(
    String submissionId,
    MediaKind kind, {
    String? reviewerUserId,
  }) => _guard(
    () =>
        _remote.media(submissionId, kind.name, reviewerUserId: reviewerUserId),
  );
}
