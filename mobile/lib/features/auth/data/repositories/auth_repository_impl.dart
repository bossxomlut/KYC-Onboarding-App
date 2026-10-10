import 'package:dio/dio.dart';

import '../../../../core/domain/result.dart';
import '../../../../core/network/api_failure.dart';
import '../../../../core/security/token_store.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';
import '../models/auth_session_model.dart';
import '../session_refresher.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._remote, this._tokens, this._refresher);
  final AuthRemoteDataSource _remote;
  final TokenStore _tokens;
  final SessionRefresher _refresher;

  Future<Result<T>> _result<T>(Future<T> Function() operation) async {
    try {
      return Success(await operation());
    } catch (error) {
      return Failure(mapApiFailure(error));
    }
  }

  Future<User> _saveSession(Future<AuthSessionModel> operation) async {
    final session = await operation;
    await _tokens.saveTokens(
        accessToken: session.accessToken, refreshToken: session.refreshToken);
    return session.user.toEntity();
  }

  @override
  Future<Result<User>> register(
          {required String email, required String password}) =>
      _result(() async =>
          (await _remote.register(email: email, password: password))
              .toEntity());
  @override
  Future<Result<User>> login(
          {required String email, required String password}) =>
      _result(
          () => _saveSession(_remote.login(email: email, password: password)));
  @override
  Future<Result<User>> verifyEmail(
          {required String email, required String code}) =>
      _result(
          () => _saveSession(_remote.verifyEmail(email: email, code: code)));
  @override
  Future<Result<void>> resendVerificationCode(String email) =>
      _result(() => _remote.resendCode(email));

  @override
  Future<Result<User?>> restoreSession() async {
    try {
      if (await _tokens.readRefreshToken() == null) return const Success(null);
      await _refresher.refreshCredentials();
      return Success((await _remote.me()).toEntity());
    } catch (error) {
      if (error is DioException &&
          {401, 403}.contains(error.response?.statusCode)) {
        try {
          await _tokens.clear();
          return const Success(null);
        } catch (storageError) {
          return Failure(mapApiFailure(storageError));
        }
      }
      return Failure(mapApiFailure(error));
    }
  }

  @override
  Future<Result<void>> logout() => _result(() async {
        final token = await _tokens.readRefreshToken();
        if (token != null) {
          try {
            await _remote.logout(token);
          } on DioException catch (error) {
            // An already revoked session has the same safe local outcome.
            if (!{401, 403}.contains(error.response?.statusCode)) rethrow;
          }
        }
        await _tokens.clear();
      });

  @override
  Future<Result<void>> requestPasswordReset(String email) =>
      _result(() => _remote.requestPasswordReset(email));
  @override
  Future<Result<void>> resetPassword(
          {required String token, required String newPassword}) =>
      _result(() async {
        await _remote.resetPassword(token: token, newPassword: newPassword);
        await _tokens.clear();
      });
}
