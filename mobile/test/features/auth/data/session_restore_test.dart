import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/core/domain/result.dart';
import 'package:kyc_onboarding/core/network/api_client.dart';
import 'package:kyc_onboarding/core/security/token_store.dart';
import 'package:kyc_onboarding/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:kyc_onboarding/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:kyc_onboarding/features/auth/data/session_refresher.dart';
import 'package:kyc_onboarding/features/auth/domain/entities/user.dart';

class MemoryTokens implements TokenStore {
  String? refreshToken = 'saved-refresh';
  @override
  String? accessToken;
  int clearCount = 0;
  @override
  Future<String?> readRefreshToken() async => refreshToken;
  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
  }

  @override
  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
    clearCount++;
  }
}

class TestAdapter implements HttpClientAdapter {
  TestAdapter(this.handler);
  final FutureOr<ResponseBody> Function(RequestOptions) handler;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => handler(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(Object value, [int status = 200]) =>
    ResponseBody.fromString(
      jsonEncode(value),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );

final userJson = {
  'id': 'user-1',
  'email': 'demo@example.test',
  'emailVerified': true,
};
final sessionJson = {
  'user': userJson,
  'accessToken': 'new-access',
  'refreshToken': 'new-refresh',
  'expiresIn': 900,
};

void main() {
  late MemoryTokens tokens;
  late Dio dio;
  late AuthRemoteDataSource remote;
  late SessionRefresher refresher;
  late AuthRepositoryImpl repository;

  setUp(() {
    tokens = MemoryTokens();
    dio = Dio(BaseOptions(baseUrl: 'http://api.test/api/v1'));
    remote = AuthRemoteDataSource(ApiClient(dio));
    refresher = SessionRefresher(remote, tokens);
    repository = AuthRepositoryImpl(remote, tokens, refresher);
  });
  tearDown(() => dio.close());

  test(
    'foreground revalidation only fetches live user without rotation',
    () async {
      final calls = <String>[];
      dio.httpClientAdapter = TestAdapter((options) {
        calls.add(options.path);
        return jsonResponse({
          'user': {...userJson, 'role': 'reviewer'},
        });
      });
      final result = await repository.revalidateSession();
      expect(result, isA<Success<User>>());
      expect((result as Success<User>).value.role, UserRole.reviewer);
      expect(calls, ['/auth/me']);
      expect(tokens.refreshToken, 'saved-refresh');
      expect(tokens.clearCount, 0);
    },
  );

  test('restore rotates credentials then retrieves server user', () async {
    final calls = <String>[];
    dio.httpClientAdapter = TestAdapter((options) {
      calls.add(options.path);
      return jsonResponse(
        options.path == '/auth/refresh' ? sessionJson : {'user': userJson},
      );
    });
    final result = await repository.restoreSession();
    expect(result, isA<Success<User?>>());
    expect((result as Success<User?>).value?.id, 'user-1');
    expect(tokens.refreshToken, 'new-refresh');
    expect(tokens.accessToken, 'new-access');
    expect(calls, ['/auth/refresh', '/auth/me']);
  });

  test('invalid refresh signs out and clears tokens', () async {
    dio.httpClientAdapter = TestAdapter(
      (_) => jsonResponse({
        'error': {'code': 'SESSION_EXPIRED', 'message': 'Sign in again.'},
      }, 401),
    );
    final result = await repository.restoreSession();
    expect(result, isA<Success<User?>>());
    expect((result as Success<User?>).value, isNull);
    expect(tokens.refreshToken, isNull);
    expect(tokens.clearCount, 1);
  });

  test('network failure retains refresh token for retry', () async {
    dio.httpClientAdapter = TestAdapter(
      (options) => throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      ),
    );
    final result = await repository.restoreSession();
    expect(result, isA<Failure<User?>>());
    expect((result as Failure<User?>).error.isNetwork, isTrue);
    expect(tokens.refreshToken, 'saved-refresh');
    expect(tokens.clearCount, 0);
  });

  test('concurrent refresh calls rotate once', () async {
    var calls = 0;
    final release = Completer<void>();
    dio.httpClientAdapter = TestAdapter((_) async {
      calls++;
      await release.future;
      return jsonResponse(sessionJson);
    });
    final first = refresher.refreshCredentials();
    final second = refresher.refreshCredentials();
    await Future<void>.delayed(Duration.zero);
    release.complete();
    await Future.wait([first, second]);
    expect(calls, 1);
    expect(tokens.refreshToken, 'new-refresh');
  });

  test(
    'late refresh does not overwrite a newly saved account session',
    () async {
      final reachedServer = Completer<void>();
      final release = Completer<void>();
      dio.httpClientAdapter = TestAdapter((_) async {
        reachedServer.complete();
        await release.future;
        return jsonResponse(sessionJson);
      });
      final operation = refresher.refreshCredentials();
      await reachedServer.future;
      await tokens.saveTokens(
        accessToken: 'another-account-access',
        refreshToken: 'another-account-refresh',
      );
      release.complete();
      await expectLater(operation, throwsA(isA<DioException>()));
      expect(tokens.accessToken, 'another-account-access');
      expect(tokens.refreshToken, 'another-account-refresh');
    },
  );

  test('successful password reset removes the revoked local session', () async {
    dio.httpClientAdapter = TestAdapter((_) => jsonResponse({'success': true}));
    final result = await repository.resetPassword(
      email: 'demo@example.test',
      code: '123456',
      newPassword: 'DemoPassword12',
    );
    expect(result, isA<Success<void>>());
    expect(tokens.refreshToken, isNull);
  });

  test('late password reset cannot clear a newer login session', () async {
    final reachedServer = Completer<void>();
    final release = Completer<void>();
    dio.httpClientAdapter = TestAdapter((_) async {
      reachedServer.complete();
      await release.future;
      return jsonResponse({'success': true});
    });
    final reset = repository.resetPassword(
      email: 'demo@example.test',
      code: '123456',
      newPassword: 'DemoPassword12',
    );
    await reachedServer.future;
    await tokens.saveTokens(
      accessToken: 'new-login-access',
      refreshToken: 'new-login-refresh',
    );
    release.complete();
    expect(await reset, isA<Success<void>>());
    expect(tokens.accessToken, 'new-login-access');
    expect(tokens.refreshToken, 'new-login-refresh');
    expect(tokens.clearCount, 0);
  });

  test('offline logout retains session and reports failure', () async {
    dio.httpClientAdapter = TestAdapter(
      (options) => throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      ),
    );
    final result = await repository.logout();
    expect(result, isA<Failure<void>>());
    expect(tokens.refreshToken, 'saved-refresh');
  });
}
