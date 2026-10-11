import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/core/domain/result.dart';
import 'package:kyc_onboarding/core/network/api_client.dart';
import 'package:kyc_onboarding/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:kyc_onboarding/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:kyc_onboarding/features/auth/data/session_refresher.dart';
import 'package:kyc_onboarding/features/auth/domain/usecases/request_password_reset.dart';
import 'package:kyc_onboarding/features/auth/domain/usecases/reset_password.dart';

import 'session_restore_test.dart' show MemoryTokens, TestAdapter, jsonResponse;

void main() {
  late Dio dio;
  late MemoryTokens tokens;
  late AuthRepositoryImpl repository;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://api.test/api/v1'));
    tokens = MemoryTokens();
    final remote = AuthRemoteDataSource(ApiClient(dio));
    repository = AuthRepositoryImpl(
      remote,
      tokens,
      SessionRefresher(remote, tokens),
    );
  });
  tearDown(() => dio.close());

  test('request reset OTP sends only the normalized email', () async {
    dio.httpClientAdapter = TestAdapter((options) {
      expect(options.path, '/auth/password/forgot');
      expect(options.data, {'email': 'person@example.test'});
      return jsonResponse({'message': 'Check your inbox for a reset code.'});
    });

    final result = await RequestPasswordReset(repository)(
      ' Person@Example.Test ',
    );
    expect(result, isA<Success<void>>());
    expect(tokens.clearCount, 0);
    expect(tokens.refreshToken, 'saved-refresh');
  });

  test('reset uses email and OTP while preserving code and password', () async {
    dio.httpClientAdapter = TestAdapter((options) {
      expect(options.path, '/auth/password/reset');
      expect(options.data, {
        'email': 'person@example.test',
        'code': '012345',
        'newPassword': ' ReplacementPass123! ',
      });
      return jsonResponse({'success': true});
    });

    final result = await ResetPassword(repository)(
      email: ' Person@Example.Test ',
      code: ' 012345 ',
      newPassword: ' ReplacementPass123! ',
    );
    expect(result, isA<Success<void>>());
    expect(tokens.clearCount, 1);
    expect(tokens.refreshToken, isNull);
  });

  test(
    'invalid reset OTP maps failure and retains the local session',
    () async {
      dio.httpClientAdapter = TestAdapter(
        (_) => jsonResponse({
          'error': {
            'code': 'RESET_OTP_INVALID',
            'message': 'Invalid reset code. Request a new code.',
          },
        }, 400),
      );

      final result = await ResetPassword(repository)(
        email: 'person@example.test',
        code: '012345',
        newPassword: 'ReplacementPass123!',
      );
      expect(result, isA<Failure<void>>());
      expect((result as Failure<void>).error.code, 'RESET_OTP_INVALID');
      expect(tokens.refreshToken, 'saved-refresh');
      expect(tokens.clearCount, 0);
    },
  );
}
