import 'package:dio/dio.dart';

import '../security/token_store.dart';
import 'api_failure.dart';

/// The server verifies bearer credentials before running any mutation. Only
/// that explicit authorization failure is replayed; timeouts are never retried.
class BearerTokenInterceptor extends Interceptor {
  BearerTokenInterceptor(this._dio, this._tokens,
      {required this.refresh, required this.invalidate, this.sessionScope});
  final Dio _dio;
  final TokenStore _tokens;
  final Future<void> Function() refresh;
  final Future<void> Function() invalidate;
  final String? Function()? sessionScope;

  bool _sameSession(RequestOptions request) =>
      sessionScope == null ||
      request.extra['authSessionScope'] == sessionScope!();

  bool _requiresBearer(String path) =>
      !path.startsWith('/auth/') || path == '/auth/me';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final accessToken = _tokens.accessToken;
    if (_requiresBearer(options.path) && accessToken != null) {
      if (!options.extra.containsKey('authSessionScope')) {
        options.extra['authSessionScope'] = sessionScope?.call();
      }
      options.headers['Authorization'] = 'Bearer $accessToken';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final error = err;
    final request = error.requestOptions;
    final code = mapApiFailure(error).code;
    if (!_requiresBearer(request.path) ||
        error.response?.statusCode != 401 ||
        code != 'SESSION_EXPIRED') {
      handler.next(error);
      return;
    }
    if (!_sameSession(request)) {
      handler.next(error);
      return;
    }
    if (request.extra['authRetried'] == true) {
      await invalidate();
      handler.next(error);
      return;
    }
    try {
      // A concurrent request may already have rotated the token.
      if (request.headers['Authorization'] == 'Bearer ${_tokens.accessToken}' ||
          _tokens.accessToken == null) {
        await refresh();
      }
      if (!_sameSession(request)) {
        handler.next(error);
        return;
      }
      final retry = request.copyWith(
        headers: {
          ...request.headers,
          'Authorization': 'Bearer ${_tokens.accessToken}'
        },
        extra: {...request.extra, 'authRetried': true},
        data: request.data is FormData
            ? (request.data as FormData).clone()
            : request.data,
      );
      handler.resolve(await _dio.fetch<Object?>(retry));
    } on DioException catch (refreshError) {
      if (_sameSession(request) &&
          (refreshError.response?.statusCode == 401 ||
              refreshError.response?.statusCode == 403)) {
        await invalidate();
      }
      handler.next(refreshError);
    } catch (unexpected) {
      handler.next(DioException(requestOptions: request, error: unexpected));
    }
  }
}
