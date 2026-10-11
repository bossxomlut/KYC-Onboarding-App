import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kyc_onboarding/app/di/dependencies.dart';
import 'package:kyc_onboarding/app/kyc_app.dart';
import 'package:kyc_onboarding/features/kyc/data/datasources/camera_datasource.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/camera_capture_crop.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';

import '../data/session_restore_test.dart'
    show MemoryTokens, TestAdapter, jsonResponse, sessionJson, userJson;

class NoCaptureCamera implements CameraDataSource {
  @override
  Future<CapturedMedia?> capture(
    MediaKind kind,
    String profileId, {
    DocumentType? documentType,
    CameraCaptureCrop? crop,
  }) async => null;
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
      final dependencies = configureDependencies(
        tokens: tokens,
        camera: NoCaptureCamera(),
      );
      var offline = true;
      dependencies<Dio>().httpClientAdapter = TestAdapter((options) {
        if (offline) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          );
        }
        return jsonResponse(switch (options.path) {
          '/auth/refresh' => sessionJson,
          '/auth/me' => {'user': userJson},
          _ => {
            'profile': {
              'id': 'kyc-1',
              'status': 'not_started',
              'nextStep': 'personal_details',
            },
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
    },
  );

  testWidgets('password reset OTP form survives a restore connection failure', (
    tester,
  ) async {
    final tokens = MemoryTokens();
    final dependencies = configureDependencies(tokens: tokens);
    dependencies<Dio>().httpClientAdapter = TestAdapter(
      (options) => throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      ),
    );
    await tester.pumpWidget(
      KycApp(
        dependencies: dependencies,
        initialLocation: '/reset-password?email=demo%40example.test',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Choose a new password'), findsOneWidget);
    expect(tokens.refreshToken, 'saved-refresh');
    await tester.ensureVisible(find.text('Use a different email'));
    await tester.tap(find.text('Use a different email'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
    expect(tokens.refreshToken, 'saved-refresh');
    await tester.pumpWidget(const SizedBox());
    await dependencies.reset();
  });

  testWidgets(
    'password reset success returns to sign in with revoked tokens removed',
    (tester) async {
      final tokens = MemoryTokens();
      final dependencies = configureDependencies(
        tokens: tokens,
        camera: NoCaptureCamera(),
      );
      dependencies<Dio>().httpClientAdapter = TestAdapter(
        (options) => jsonResponse(switch (options.path) {
          '/auth/refresh' => sessionJson,
          '/auth/me' => {'user': userJson},
          _ => {'success': true},
        }),
      );
      await tester.pumpWidget(
        KycApp(
          dependencies: dependencies,
          initialLocation: '/reset-password?email=demo%40example.test',
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('otp-input')), '012345');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'New password'),
        'NewPassword123',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm new password'),
        'NewPassword123',
      );
      await tester.ensureVisible(find.text('Change password'));
      await tester.tap(find.text('Change password'));
      await tester.pumpAndSettle();
      expect(tokens.refreshToken, isNull);
      expect(
        find.text(
          'Your password has been changed. Sign in with your new password.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Back to sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome back'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await dependencies.reset();
    },
  );

  testWidgets(
    'forgot password opens OTP form with normalized email and cooldown',
    (tester) async {
      final tokens = MemoryTokens()..refreshToken = null;
      final dependencies = configureDependencies(tokens: tokens);
      final requests = <RequestOptions>[];
      dependencies<Dio>().httpClientAdapter = TestAdapter((options) {
        requests.add(options);
        return jsonResponse({
          'message': 'If an account exists, a code was sent.',
        });
      });
      await tester.pumpWidget(
        KycApp(dependencies: dependencies, initialLocation: '/forgot-password'),
      );
      await tester.pumpAndSettle();
      (tester.widget<MaterialApp>(find.byType(MaterialApp)).routerConfig!
              as GoRouter)
          .go('/forgot-password');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        ' Demo@Example.Test ',
      );
      await tester.tap(find.text('Send reset code'));
      await tester.pumpAndSettle();
      expect(requests.single.path, '/auth/password/forgot');
      expect(requests.single.data, {'email': 'demo@example.test'});
      expect(find.byKey(const ValueKey('otp-input')), findsOneWidget);
      expect(find.textContaining('demo@example.test'), findsOneWidget);
      expect(find.textContaining('Resend code in '), findsOneWidget);
      await tester.ensureVisible(find.text('Use a different email'));
      await tester.tap(find.text('Use a different email'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await dependencies.reset();
    },
  );

  testWidgets('reset route without email opens forgot password form', (
    tester,
  ) async {
    final tokens = MemoryTokens()..refreshToken = null;
    final dependencies = configureDependencies(tokens: tokens);
    await tester.pumpWidget(
      KycApp(dependencies: dependencies, initialLocation: '/reset-password'),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
    expect(find.byKey(const ValueKey('otp-input')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await dependencies.reset();
  });

  testWidgets('failed reset code request keeps email for retry', (
    tester,
  ) async {
    final tokens = MemoryTokens()..refreshToken = null;
    final dependencies = configureDependencies(tokens: tokens);
    var offline = true;
    var requests = 0;
    dependencies<Dio>().httpClientAdapter = TestAdapter((options) {
      requests++;
      if (offline) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      }
      return jsonResponse({'message': 'Code sent.'});
    });
    await tester.pumpWidget(
      KycApp(dependencies: dependencies, initialLocation: '/forgot-password'),
    );
    await tester.pumpAndSettle();
    (tester.widget<MaterialApp>(find.byType(MaterialApp)).routerConfig!
            as GoRouter)
        .go('/forgot-password');
    await tester.pumpAndSettle();
    final emailField = find.widgetWithText(TextFormField, 'Email');
    await tester.enterText(emailField, 'demo@example.test');
    await tester.tap(find.text('Send reset code'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextFormField>(emailField).controller!.text,
      'demo@example.test',
    );
    offline = false;
    await tester.tap(find.text('Send reset code'));
    await tester.pumpAndSettle();
    expect(requests, 2);
    expect(find.byKey(const ValueKey('otp-input')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await dependencies.reset();
  });
}
