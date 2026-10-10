import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/app/di/dependencies.dart';
import 'package:kyc_onboarding/app/kyc_app.dart';
import 'package:kyc_onboarding/features/kyc/data/datasources/camera_datasource.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';

import '../data/session_restore_test.dart'
    show MemoryTokens, TestAdapter, jsonResponse, sessionJson, userJson;

class NoCaptureCamera implements CameraDataSource {
  @override
  Future<CapturedMedia?> capture(MediaKind kind, String profileId,
          {DocumentType? documentType}) async =>
      null;
  @override
  Future<CapturedMedia?> recover(MediaKind kind, String profileId) async =>
      null;
  @override
  Future<void> remove(CapturedMedia media) async {}
  @override
  Future<void> discard(String profileId) async {}
}

void main() {
  testWidgets(
      'connection failure preserves saved session and retry resumes server state',
      (tester) async {
    final tokens = MemoryTokens();
    final dependencies =
        configureDependencies(tokens: tokens, camera: NoCaptureCamera());
    var offline = true;
    dependencies<Dio>().httpClientAdapter = TestAdapter((options) {
      if (offline) {
        throw DioException(
            requestOptions: options, type: DioExceptionType.connectionError);
      }
      return jsonResponse(switch (options.path) {
        '/auth/refresh' => sessionJson,
        '/auth/me' => {'user': userJson},
        _ => {
            'profile': {
              'id': 'kyc-1',
              'status': 'not_started',
              'nextStep': 'personal_details'
            }
          },
      });
    });
    await tester.pumpWidget(KycApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    expect(find.text('Let’s reconnect'), findsOneWidget);
    expect(find.text('Retry connection'), findsOneWidget);
    expect(tokens.refreshToken, 'saved-refresh');
    offline = false;
    await tester.tap(find.text('Retry connection'));
    await tester.pumpAndSettle();
    expect(find.text('Start verification'), findsOneWidget);
    expect(tokens.refreshToken, 'new-refresh');
    await tester.pumpWidget(const SizedBox());
    await dependencies.reset();
  });

  testWidgets('password reset deep link survives a restore connection failure',
      (tester) async {
    final tokens = MemoryTokens();
    final dependencies = configureDependencies(tokens: tokens);
    dependencies<Dio>().httpClientAdapter = TestAdapter((options) =>
        throw DioException(
            requestOptions: options, type: DioExceptionType.connectionError));
    await tester.pumpWidget(KycApp(
        dependencies: dependencies,
        initialLocation: '/reset-password?token=demo-token'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a new password'), findsOneWidget);
    expect(tokens.refreshToken, 'saved-refresh');
    await tester.pumpWidget(const SizedBox());
    await dependencies.reset();
  });

  testWidgets(
      'password reset success returns to sign in with revoked tokens removed',
      (tester) async {
    final tokens = MemoryTokens();
    final dependencies =
        configureDependencies(tokens: tokens, camera: NoCaptureCamera());
    dependencies<Dio>().httpClientAdapter =
        TestAdapter((options) => jsonResponse(switch (options.path) {
              '/auth/refresh' => sessionJson,
              '/auth/me' => {'user': userJson},
              _ => {'success': true},
            }));
    await tester.pumpWidget(KycApp(
        dependencies: dependencies,
        initialLocation: '/reset-password?token=demo-reset-token'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'New password'), 'NewPassword123');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm new password'),
        'NewPassword123');
    await tester.ensureVisible(find.text('Change password'));
    await tester.tap(find.text('Change password'));
    await tester.pumpAndSettle();
    expect(tokens.refreshToken, isNull);
    expect(
        find.text(
            'Your password has been changed. Sign in with your new password.'),
        findsOneWidget);
    await tester.tap(find.text('Back to sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await dependencies.reset();
  });
}
