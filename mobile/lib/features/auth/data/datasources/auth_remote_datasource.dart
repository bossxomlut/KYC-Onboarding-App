import '../../../../core/network/api_client.dart';
import '../models/auth_session_model.dart';
import '../models/user_model.dart';

class AuthRemoteDataSource {
  AuthRemoteDataSource(this._api);
  final ApiClient _api;

  Future<UserModel> register(
      {required String email, required String password}) async {
    final response = await _api
        .post('/auth/register', data: {'email': email, 'password': password});
    return UserModel.fromJson(response['user'] as Map<String, dynamic>);
  }

  Future<AuthSessionModel> login(
          {required String email, required String password}) async =>
      AuthSessionModel.fromJson(await _api
          .post('/auth/login', data: {'email': email, 'password': password}));

  Future<AuthSessionModel> verifyEmail(
          {required String email, required String code}) async =>
      AuthSessionModel.fromJson(await _api
          .post('/auth/email/verify', data: {'email': email, 'code': code}));

  Future<AuthSessionModel> refresh(String refreshToken) async =>
      AuthSessionModel.fromJson(await _api
          .post('/auth/refresh', data: {'refreshToken': refreshToken}));

  Future<UserModel> me() async => UserModel.fromJson(
      (await _api.get('/auth/me'))['user'] as Map<String, dynamic>);

  Future<void> resendCode(String email) async =>
      _api.post('/auth/email/resend', data: {'email': email});
  Future<void> logout(String refreshToken) async =>
      _api.post('/auth/logout', data: {'refreshToken': refreshToken});
  Future<void> requestPasswordReset(String email) async =>
      _api.post('/auth/password/forgot', data: {'email': email});
  Future<void> resetPassword(
          {required String token, required String newPassword}) async =>
      _api.post('/auth/password/reset',
          data: {'token': token, 'newPassword': newPassword});
}
