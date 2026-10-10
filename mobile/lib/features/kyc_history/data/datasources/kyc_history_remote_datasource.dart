import 'dart:typed_data';
import '../../../../core/network/api_client.dart';

class KycHistoryRemoteDataSource {
  const KycHistoryRemoteDataSource(this._api);
  final ApiClient _api;
  String _base(String? userId) => userId == null
      ? '/kyc/history'
      : '/reviews/${Uri.encodeComponent(userId)}/history';
  Future<Map<String, dynamic>> load({
    required int offset,
    required int limit,
    String? reviewerUserId,
  }) => _api.get('${_base(reviewerUserId)}?limit=$limit&offset=$offset');
  Future<Uint8List> media(
    String submissionId,
    String kind, {
    String? reviewerUserId,
  }) => _api.bytes(
    '${_base(reviewerUserId)}/${Uri.encodeComponent(submissionId)}/media/$kind',
  );
}
