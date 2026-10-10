import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kyc_onboarding/app/di/dependencies.dart';
import 'package:kyc_onboarding/app/kyc_app.dart';
import 'package:kyc_onboarding/features/auth/presentation/bloc/auth_session_cubit.dart';
import 'package:kyc_onboarding/features/auth/presentation/pages/reset_password_page.dart';
import 'package:kyc_onboarding/features/kyc/presentation/bloc/kyc_cubit.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/home_page.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/personal_details_page.dart';
import '../features/auth/data/session_restore_test.dart'
    show MemoryTokens, TestAdapter, jsonResponse, sessionJson, userJson;
import '../features/auth/presentation/app_session_retry_test.dart'
    show NoCaptureCamera;
import 'system_back_test.dart' show profileJson;
import '../features/kyc_history/kyc_history_data_test.dart' show submissionJson;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> background(WidgetTester tester) async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
  }

  Future<void> resume(WidgetTester tester) async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('focus loss alone does not reload KYC or session', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.pump(tester);
    fixture.calls.clear();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(fixture.calls, isEmpty);
  });

  testWidgets('foreground verifies session then updates KYC in the same flow', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.pump(tester);
    final flow = tester.element(find.byType(HomePage)).read<KycCubit>();
    fixture.calls.clear();
    await background(tester);
    fixture.profile = {
      ...fixture.profile,
      'status': 'verified',
      'nextStep': 'result',
    };
    await resume(tester);
    await tester.pumpAndSettle();
    expect(fixture.calls, ['/auth/me', '/kyc']);
    expect(tester.element(find.byType(HomePage)).read<KycCubit>(), same(flow));
    expect(find.text('Verified'), findsOneWidget);
    expect(fixture.router.routeInformationProvider.value.uri.path, '/');
  });

  testWidgets('delayed foreground session check preserves personal draft', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.pump(tester, location: '/kyc/details');
    final flow = tester
        .element(find.byType(PersonalDetailsPage))
        .read<KycCubit>();
    final field = find.byKey(const Key('fullName'));
    await tester.enterText(field, 'Unsaved Foreground Draft');
    fixture.calls.clear();
    fixture.meGate = Completer<void>();
    await background(tester);
    await resume(tester);
    expect(fixture.calls, ['/auth/me']);
    expect(find.byType(PersonalDetailsPage), findsOneWidget);
    expect(
      tester.widget<TextFormField>(field).controller?.text ??
          tester.widget<TextFormField>(field).initialValue,
      'Unsaved Foreground Draft',
    );
    fixture.meGate!.complete();
    await tester.pumpAndSettle();
    expect(
      tester.element(find.byType(PersonalDetailsPage)).read<KycCubit>(),
      same(flow),
    );
    expect(find.text('Unsaved Foreground Draft'), findsOneWidget);
  });

  testWidgets('access refresh preserves the reason being composed', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.pump(tester, location: '/access');
    await tester.enterText(
      find.byKey(const Key('request-reason')),
      'I need to review applicant documents.',
    );
    fixture.calls.clear();
    await background(tester);
    await resume(tester);
    await tester.pumpAndSettle();
    expect(fixture.calls, contains('/access/role-request'));
    expect(fixture.calls.first, '/auth/me');
    expect(find.text('I need to review applicant documents.'), findsOneWidget);
  });

  testWidgets('revoked reviewer role removes cached detail and confirmation', (
    tester,
  ) async {
    final fixture = _Fixture()..role = 'reviewer';
    await fixture.pump(tester, location: '/reviews/applicant');
    await tester.ensureVisible(find.byKey(const Key('review-approve')));
    await tester.tap(find.byKey(const Key('review-approve')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await background(tester);
    fixture.role = 'user';
    fixture.calls.clear();
    await resume(tester);
    await tester.pumpAndSettle();
    expect(fixture.router.routeInformationProvider.value.uri.path, '/access');
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Demo Applicant'), findsNothing);
    expect(fixture.calls, isNot(contains('/reviews/applicant/decision')));
  });

  testWidgets('offline revalidation retains the page and retries on demand', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.pump(tester, location: '/kyc/details');
    await tester.enterText(
      find.byKey(const Key('fullName')),
      'Draft while offline',
    );
    await background(tester);
    fixture.offline = true;
    await resume(tester);
    await tester.pumpAndSettle();
    expect(find.byType(PersonalDetailsPage), findsOneWidget);
    expect(find.text('Draft while offline'), findsOneWidget);
    expect(find.byKey(const Key('retry-foreground')), findsOneWidget);
    fixture.offline = false;
    fixture.calls.clear();
    await tester.tap(find.byKey(const Key('retry-foreground')));
    await tester.pumpAndSettle();
    expect(fixture.calls, ['/auth/me', '/kyc']);
    expect(find.byKey(const Key('retry-foreground')), findsNothing);
    expect(find.text('Draft while offline'), findsOneWidget);
  });

  testWidgets('a second resume cannot reuse a delayed old permission check', (
    tester,
  ) async {
    final fixture = _Fixture()..role = 'reviewer';
    await fixture.pump(tester, location: '/reviews/applicant');
    fixture.calls.clear();
    fixture.meGate = Completer<void>();
    await background(tester);
    await resume(tester);
    expect(fixture.calls, ['/auth/me']);
    await background(tester);
    fixture.role = 'user';
    await resume(tester);
    fixture.meGate!.complete();
    await tester.pumpAndSettle();
    expect(fixture.calls.take(2), ['/auth/me', '/auth/me']);
    expect(fixture.router.routeInformationProvider.value.uri.path, '/access');
    expect(find.text('Demo Applicant'), findsNothing);
  });

  testWidgets('obsolete reset success still invalidates the app session', (
    tester,
  ) async {
    final fixture = _Fixture()..resetGate = Completer<void>();
    await fixture.pump(tester, location: '/reset-password?token=old-token');
    final session = tester
        .element(find.byType(ResetPasswordPage))
        .read<AuthSessionCubit>();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'New password'),
      'NewPassword1234',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm new password'),
      'NewPassword1234',
    );
    await tester.ensureVisible(find.text('Change password'));
    await tester.tap(find.text('Change password'));
    await tester.pump();
    fixture.router.go('/reset-password?token=new-token');
    await tester.pumpAndSettle();
    fixture.resetGate!.complete();
    await tester.pumpAndSettle();
    expect(session.state, isA<AuthSignedOut>());
    final tokenField = find.widgetWithText(TextFormField, 'Reset token');
    expect(
      tester.widget<TextFormField>(tokenField).controller!.text,
      'new-token',
    );
    expect(
      find.text(
        'Your password has been changed. Sign in with your new password.',
      ),
      findsNothing,
    );
  });

  for (final entry in {
    '/admin': ('super_admin', '/admin/users'),
    '/reviews': ('reviewer', '/reviews'),
    '/kyc/history': ('user', '/kyc/history'),
    '/reviews/applicant/history': ('reviewer', '/reviews/applicant/history'),
  }.entries) {
    testWidgets('foreground refreshes ${entry.key} after live session check', (
      tester,
    ) async {
      final fixture = _Fixture()..role = entry.value.$1;
      await fixture.pump(tester, location: entry.key);
      fixture.calls.clear();
      await background(tester);
      await resume(tester);
      await tester.pumpAndSettle();
      expect(fixture.calls.first, '/auth/me');
      expect(
        fixture.calls.map((path) => Uri.parse(path).path),
        contains(entry.value.$2),
      );
      expect(fixture.router.routeInformationProvider.value.uri.path, entry.key);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'history sheet stays open with photos and updated review status',
    (tester) async {
      final fixture = _Fixture()..historySubmission = {...submissionJson};
      await fixture.pump(tester, location: '/kyc/history');
      await tester.tap(
        find.byKey(const Key('history-submission-submission-1')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('history-detail-close')), findsOneWidget);
      await background(tester);
      fixture.historySubmission = {
        ...submissionJson,
        'profile': <String, dynamic>{
          ...submissionJson['profile'] as Map<String, dynamic>,
          'status': 'verified',
        },
        'review': null,
      };
      await resume(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('history-detail-close')), findsOneWidget);
      expect(find.text('Original Applicant'), findsOneWidget);
      expect(find.text('Verified'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Fixture {
  final calls = <String>[];
  String role = 'user';
  bool offline = false;
  Completer<void>? meGate;
  Completer<void>? resetGate;
  Map<String, Object?> profile = {...profileJson};
  Map<String, dynamic>? historySubmission;
  late GoRouter router;

  Future<void> pump(WidgetTester tester, {String location = '/'}) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final dependencies = configureDependencies(
      tokens: MemoryTokens(),
      camera: NoCaptureCamera(),
    );
    dependencies<Dio>().httpClientAdapter = TestAdapter((options) async {
      calls.add(options.path);
      final user = {...userJson, 'role': role};
      if (options.path == '/auth/me' && meGate != null) {
        await meGate!.future;
      }
      if (options.path == '/auth/password/reset' && resetGate != null) {
        await resetGate!.future;
      }
      if (offline) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      }
      if (options.path.contains('/media/')) {
        return ResponseBody.fromBytes(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aSu8AAAAASUVORK5CYII=',
          ),
          200,
          headers: {
            Headers.contentTypeHeader: ['image/png'],
          },
        );
      }
      return jsonResponse(switch (Uri.parse(options.path).path) {
        '/auth/refresh' => {...sessionJson, 'user': user},
        '/auth/me' => {'user': user},
        '/access/role-request' => {'request': null},
        '/kyc' => {'profile': profile},
        '/kyc/history' => {
          'submissions': [if (historySubmission != null) historySubmission],
          'total': historySubmission == null ? 0 : 1,
        },
        '/reviews/applicant' => {
          'submissionId': '00000000-0000-4000-8000-000000000001',
          'user': {'id': 'applicant', 'email': 'applicant@example.test'},
          'profile': {
            ...profileJson,
            'status': 'pending_review',
            'nextStep': 'result',
          },
        },
        _ => {
          'submissions': [],
          'profiles': [],
          'users': [],
          'requests': [],
          'total': 0,
        },
      });
    });
    addTearDown(() async {
      if (meGate != null && !meGate!.isCompleted) meGate!.complete();
      if (resetGate != null && !resetGate!.isCompleted) resetGate!.complete();
      await tester.pumpWidget(const SizedBox());
      await dependencies.reset();
    });
    await tester.pumpWidget(KycApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    router =
        tester.widget<MaterialApp>(find.byType(MaterialApp)).routerConfig!
            as GoRouter;
    router.go(location);
    await tester.pumpAndSettle();
  }
}
