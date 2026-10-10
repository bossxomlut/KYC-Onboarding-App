import 'package:dio/dio.dart';

import '../../../core/security/token_store.dart';
import 'datasources/auth_remote_datasource.dart';

/// Refresh rotation is shared by startup restore and all unauthorized calls.
class SessionRefresher {
  SessionRefresher(this._remote, this._tokens);
  final AuthRemoteDataSource _remote;
  final TokenStore _tokens;
  Future<void>? _inFlight;

  Future<void> refreshCredentials() {
    final existing = _inFlight;
    if (existing != null) return existing;
    final operation = _refresh();
    _inFlight = operation;
    return operation.whenComplete(() => _inFlight = null);
  }

  Future<void> _refresh() async {
    final token = await _tokens.readRefreshToken();
    if (token == null) {
      throw DioException(
        requestOptions: RequestOptions(path: '/auth/refresh'),
        response: Response(
          requestOptions: RequestOptions(path: '/auth/refresh'),
          statusCode: 401,
          data: {
            'error': {
              'code': 'SESSION_EXPIRED',
              'message': 'Please sign in again.',
            },
          },
        ),
        type: DioExceptionType.badResponse,
      );
    }
    final session = await _remote.refresh(token);
    final store = _tokens;
    if (store is RotatingTokenStore) {
      final saved = await store.rotateTokens(
        expectedRefreshToken: token,
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
      );
      if (!saved) throw _sessionChanged();
    } else {
      if (await store.readRefreshToken() != token) throw _sessionChanged();
      await store.saveTokens(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
      );
    }
  }

  DioException _sessionChanged() => DioException(
    requestOptions: RequestOptions(path: '/auth/refresh'),
    type: DioExceptionType.cancel,
    error: 'Session changed during refresh.',
  );
}
