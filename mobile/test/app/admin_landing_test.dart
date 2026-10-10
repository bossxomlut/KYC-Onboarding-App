import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/app/di/dependencies.dart';
import 'package:kyc_onboarding/app/kyc_app.dart';
import '../features/auth/data/session_restore_test.dart'
    show MemoryTokens, TestAdapter, jsonResponse, sessionJson, userJson;

final _admin = {...userJson, 'email': 'admin@kyc.com', 'role': 'super_admin'};

void main() {
  for (final initialLocation in [null, '/kyc/status', '/kyc/details']) {
    testWidgets('admin landing $initialLocation never requests applicant KYC', (
      tester,
    ) async {
      final dependencies = configureDependencies(tokens: MemoryTokens());
      final calls = <String>[];
      dependencies<Dio>().httpClientAdapter = TestAdapter((options) {
        calls.add(options.path);
        return jsonResponse(switch (options.path) {
          '/auth/refresh' => {...sessionJson, 'user': _admin},
          '/auth/me' => {'user': _admin},
          _ => {
            'profile': {
              'id': 'p',
              'status': 'not_started',
              'nextStep': 'personal_details',
            },
          },
        });
      });
      await tester.pumpWidget(
        KycApp(dependencies: dependencies, initialLocation: initialLocation),
      );
      await tester.pumpAndSettle();
      expect(find.text('Manage accounts'), findsOneWidget);
      expect(find.text('Review profiles'), findsOneWidget);
      expect(calls.where((path) => path.startsWith('/kyc')), isEmpty);
      expect(find.byKey(const Key('kyc-status')), findsNothing);
      expect(find.byKey(const Key('kyc-next')), findsNothing);
      expect(find.text('Your verification'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await dependencies.reset();
    });
  }

  testWidgets('admin logout clears the session without a KYC provider', (
    tester,
  ) async {
    final tokens = MemoryTokens();
    final dependencies = configureDependencies(tokens: tokens);
    final calls = <String>[];
    dependencies<Dio>().httpClientAdapter = TestAdapter((options) {
      calls.add(options.path);
      return jsonResponse(switch (options.path) {
        '/auth/refresh' => {...sessionJson, 'user': _admin},
        '/auth/me' => {'user': _admin},
        _ => {'success': true},
      });
    });
    await tester.pumpWidget(KycApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logout')));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(tokens.refreshToken, isNull);
    expect(calls.where((path) => path.startsWith('/kyc')), isEmpty);
    expect(calls.where((path) => path == '/auth/logout'), hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await dependencies.reset();
  });

  testWidgets(
    'admin logout stays disabled while pending and shows a retryable failure',
    (tester) async {
      final dependencies = configureDependencies(tokens: MemoryTokens());
      final release = Completer<void>();
      dependencies<Dio>().httpClientAdapter = TestAdapter((options) async {
        if (options.path == '/auth/logout') {
          await release.future;
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          );
        }
        return jsonResponse(switch (options.path) {
          '/auth/refresh' => {...sessionJson, 'user': _admin},
          '/auth/me' => {'user': _admin},
          _ => {
            'profile': {
              'id': 'p',
              'status': 'not_started',
              'nextStep': 'personal_details',
            },
          },
        });
      });
      await tester.pumpWidget(KycApp(dependencies: dependencies));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('logout')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.widget<IconButton>(find.byKey(const Key('logout'))).onPressed,
        isNull,
      );
      release.complete();
      await tester.pumpAndSettle();
      expect(
        tester.widget<IconButton>(find.byKey(const Key('logout'))).onPressed,
        isNotNull,
      );
      expect(find.text('Manage accounts'), findsOneWidget);
      expect(
        find.textContaining('connection', findRichText: true),
        findsWidgets,
      );
      await tester.pumpWidget(const SizedBox());
      await dependencies.reset();
    },
  );
}
