import 'dart:typed_data';
import '../../../../core/network/api_client.dart';

class AccessRemoteDataSource {
  const AccessRemoteDataSource(this._api);
  final ApiClient _api;
  Future<Map<String, dynamic>> currentUser() => _api.get('/auth/me');
  Future<Map<String, dynamic>> ownRequest() => _api.get('/access/role-request');
  Future<Map<String, dynamic>> requestReviewer(String reason) =>
      _api.post('/access/role-request', data: {'reason': reason});
  Future<Map<String, dynamic>> users(int offset) =>
      _api.get('/admin/users?limit=50&offset=$offset');
  Future<Map<String, dynamic>> createUser(Map<String, dynamic> body) =>
      _api.post('/admin/users', data: body);
  Future<Map<String, dynamic>> changeRole(
    String id,
    Map<String, dynamic> body,
  ) => _api.put('/admin/users/${Uri.encodeComponent(id)}/role', data: body);
  Future<Map<String, dynamic>> requests(int offset) =>
      _api.get('/admin/role-requests?limit=50&offset=$offset');
  Future<Map<String, dynamic>> decideRequest(
    String id,
    Map<String, dynamic> body,
  ) => _api.post(
    '/admin/role-requests/${Uri.encodeComponent(id)}/decision',
    data: body,
  );
  Future<Map<String, dynamic>> reviewQueue(int offset) =>
      _api.get('/reviews?limit=50&offset=$offset');
  Future<Map<String, dynamic>> reviewDetail(String id) =>
      _api.get('/reviews/${Uri.encodeComponent(id)}');
  Future<Uint8List> reviewMedia(
    String id,
    String kind, {
    required String submissionId,
  }) => _api.bytes(
    '/reviews/${Uri.encodeComponent(id)}/media/$kind?submissionId=${Uri.encodeQueryComponent(submissionId)}',
  );
  Future<Map<String, dynamic>> decideProfile(
    String id,
    Map<String, dynamic> body,
  ) => _api.post('/reviews/${Uri.encodeComponent(id)}/decision', data: body);
}
