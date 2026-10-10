import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/core/network/api_client.dart';
import 'package:kyc_onboarding/core/network/bearer_token_interceptor.dart';
import 'package:kyc_onboarding/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:kyc_onboarding/features/auth/data/session_refresher.dart';

import 'session_restore_test.dart'
    show MemoryTokens, TestAdapter, jsonResponse, sessionJson;

void main() {
  late Dio dio;
  late MemoryTokens tokens;
  late SessionRefresher refresher;
  late ApiClient api;
  var invalidations = 0;
  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://api.test/api/v1'));
    tokens = MemoryTokens()..accessToken = 'old-access';
    api = ApiClient(dio);
    refresher = SessionRefresher(AuthRemoteDataSource(api), tokens);
    invalidations = 0;
    dio.interceptors.add(BearerTokenInterceptor(dio, tokens,
        refresh: refresher.refreshCredentials, invalidate: () async {
      invalidations++;
      await tokens.clear();
    }));
  });
  tearDown(() => dio.close());

  test('concurrent unauthorized calls share rotation and retry once', () async {
    var refreshes = 0;
    var mutations = 0;
    dio.httpClientAdapter = TestAdapter((options) async {
      if (options.path == '/auth/refresh') {
        refreshes++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return jsonResponse(sessionJson);
      }
      if (options.headers['Authorization'] == 'Bearer old-access') {
        return jsonResponse({
          'error': {'code': 'SESSION_EXPIRED', 'message': 'Expired'}
        }, 401);
      }
      mutations++;
      return jsonResponse({'ok': true});
    });
    final results =
        await Future.wait([api.post('/kyc/submit'), api.get('/kyc')]);
    expect(results.every((result) => result['ok'] == true), isTrue);
    expect(refreshes, 1);
    expect(mutations, 2);
    expect(invalidations, 0);
  });

  test('timeout does not automatically replay a mutation', () async {
    var attempts = 0;
    dio.httpClientAdapter = TestAdapter((options) {
      attempts++;
      throw DioException(
          requestOptions: options, type: DioExceptionType.receiveTimeout);
    });
    await expectLater(api.post('/kyc/submit'), throwsA(isA<DioException>()));
    expect(attempts, 1);
    expect(tokens.refreshToken, isNotNull);
  });

  test('old account request never retries under a newly signed-in account',
      () async {
    var scope = 'account-a:1';
    var calls = 0;
    dio.interceptors.clear();
    dio.interceptors.add(BearerTokenInterceptor(dio, tokens,
        refresh: refresher.refreshCredentials,
        invalidate: () async {
          invalidations++;
        },
        sessionScope: () => scope));
    dio.httpClientAdapter = TestAdapter((options) async {
      calls++;
      scope = 'account-b:2';
      await tokens.saveTokens(
          accessToken: 'account-b-access', refreshToken: 'account-b-refresh');
      return jsonResponse({
        'error': {'code': 'SESSION_EXPIRED', 'message': 'Expired'}
      }, 401);
    });
    await expectLater(api.post('/kyc/submit'), throwsA(isA<DioException>()));
    expect(calls, 1);
    expect(invalidations, 0);
    expect(tokens.accessToken, 'account-b-access');
  });

  test('binary private media requests refresh expired credentials', () async {
    var refreshes = 0;
    dio.httpClientAdapter = TestAdapter((options) {
      if (options.path == '/auth/refresh') {
        refreshes++;
        return jsonResponse(sessionJson);
      }
      if (options.headers['Authorization'] == 'Bearer old-access') {
        return ResponseBody.fromBytes(
            utf8.encode(jsonEncode({
              'error': {'code': 'SESSION_EXPIRED', 'message': 'Expired'}
            })),
            401,
            headers: {
              Headers.contentTypeHeader: ['application/json']
            });
      }
      return ResponseBody.fromBytes(Uint8List.fromList([1, 2, 3]), 200,
          headers: {
            Headers.contentTypeHeader: ['image/jpeg']
          });
    });
    expect(await api.bytes('/kyc/media/document'), [1, 2, 3]);
    expect(refreshes, 1);
  });
}
