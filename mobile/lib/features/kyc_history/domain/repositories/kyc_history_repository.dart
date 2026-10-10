import 'dart:typed_data';
import '../../../../core/domain/result.dart';
import '../../../kyc/domain/entities/kyc_profile.dart';
import '../entities/kyc_history.dart';

abstract interface class KycHistoryRepository {
  Future<Result<KycHistoryPageResult>> load({
    int offset = 0,
    int limit = 20,
    String? reviewerUserId,
  });
  Future<Result<Uint8List>> media(
    String submissionId,
    MediaKind kind, {
    String? reviewerUserId,
  });
}
