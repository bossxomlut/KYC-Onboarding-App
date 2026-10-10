import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:kyc_onboarding/app/di/dependencies.dart';
import 'package:kyc_onboarding/app/kyc_app.dart';
import 'package:kyc_onboarding/features/access/presentation/pages/admin_home_page.dart';
import 'package:kyc_onboarding/features/auth/domain/entities/user.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';
import 'package:kyc_onboarding/features/kyc/presentation/bloc/kyc_cubit.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/home_page.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/personal_details_page.dart';
import '../features/auth/data/session_restore_test.dart'
    show MemoryTokens, TestAdapter, jsonResponse, sessionJson, userJson;
import '../features/auth/presentation/app_session_retry_test.dart'
    show NoCaptureCamera;

void main() {
  late int systemPopCount;
  setUp(() {
    systemPopCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemNavigator.pop') systemPopCount++;
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  for (final entry in {
    '/kyc/details': UserRole.user,
    '/kyc/document': UserRole.user,
    '/kyc/selfie': UserRole.user,
    '/kyc/review': UserRole.user,
    '/kyc/status': UserRole.user,
    '/access': UserRole.user,
    '/admin': UserRole.superAdmin,
    '/reviews': UserRole.reviewer,
    '/reviews/applicant': UserRole.reviewer,
    '/kyc/history': UserRole.user,
    '/reviews/applicant/history': UserRole.reviewer,
  }.entries) {
    testWidgets('device Back from ${entry.key} returns home', (tester) async {
      final (_, router) = await pumpApp(
        tester,
        location: entry.key,
        role: entry.value,
      );
      expect(router.routeInformationProvider.value.uri.path, entry.key);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(
        find.byType(
          entry.value == UserRole.superAdmin ? AdminHomePage : HomePage,
        ),
        findsOneWidget,
      );
      expect(systemPopCount, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Home device Back remains available to the operating system', (
    tester,
  ) async {
    final (_, router) = await pumpApp(tester, location: '/');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(systemPopCount, 1);
  });

  testWidgets('device Back closes the date picker before returning home', (
    tester,
  ) async {
    final (_, router) = await pumpApp(tester, location: '/kyc/details');
    final cubit = tester
        .element(find.byType(PersonalDetailsPage))
        .read<KycCubit>();
    await tester.ensureVisible(find.byKey(const Key('dateOfBirth')));
    await tester.tap(find.byKey(const Key('dateOfBirth')));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoDatePicker), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoDatePicker), findsNothing);
    expect(router.routeInformationProvider.value.uri.path, '/kyc/details');
    expect(systemPopCount, 0);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(tester.element(find.byType(HomePage)).read<KycCubit>(), same(cubit));
    expect(cubit.isClosed, isFalse);
    expect(systemPopCount, 0);
  });

  testWidgets('device Back closes submitted profile preview before home', (
    tester,
  ) async {
    final (_, router) = await pumpApp(
      tester,
      location: '/kyc/status',
      profile: {
        ...profileJson,
        'status': 'pending_review',
        'nextStep': 'result',
      },
    );
    await tester.ensureVisible(find.byKey(const Key('view-submitted-profile')));
    await tester.tap(find.byKey(const Key('view-submitted-profile')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('close-submitted-profile')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('close-submitted-profile')), findsNothing);
    expect(router.routeInformationProvider.value.uri.path, '/kyc/status');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(systemPopCount, 0);
  });

  testWidgets('device Back closes a review dialog before returning home', (
    tester,
  ) async {
    final (_, router) = await pumpApp(
      tester,
      location: '/reviews/applicant',
      role: UserRole.reviewer,
    );
    await tester.ensureVisible(find.byKey(const Key('review-approve')));
    await tester.tap(find.byKey(const Key('review-approve')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      router.routeInformationProvider.value.uri.path,
      '/reviews/applicant',
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(systemPopCount, 0);
  });

  testWidgets('device Back works before the KYC profile finishes loading', (
    tester,
  ) async {
    final gate = Completer<void>();
    final (_, router) = await pumpApp(
      tester,
      location: '/kyc/document',
      loadGate: gate,
      settle: false,
    );
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(systemPopCount, 0);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('device Back works when loading a KYC profile fails', (
    tester,
  ) async {
    final (_, router) = await pumpApp(
      tester,
      location: '/kyc/document',
      loadFailure: true,
    );
    expect(find.text('Retry'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(systemPopCount, 0);
  });

  testWidgets('submission finishing after device Back keeps the user home', (
    tester,
  ) async {
    final gate = Completer<void>();
    final (_, router) = await pumpApp(
      tester,
      location: '/kyc/review',
      submitGate: gate,
    );
    final cubit = tester
        .element(find.byKey(const Key('submit-kyc')))
        .read<KycCubit>();
    await tester.ensureVisible(find.byKey(const Key('submit-kyc')));
    await tester.tap(find.byKey(const Key('submit-kyc')));
    await tester.pump();
    expect(cubit.state.busy, isTrue);
    await tester.binding.handlePopRoute();
    gate.complete();
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(tester.element(find.byType(HomePage)).read<KycCubit>(), same(cubit));
    expect(cubit.isClosed, isFalse);
    expect(cubit.state.profile!.status, KycStatus.pendingReview);
    expect(systemPopCount, 0);
    expect(tester.takeException(), isNull);
  });
}

Future<(GetIt, GoRouter)> pumpApp(
  WidgetTester tester, {
  required String location,
  UserRole role = UserRole.user,
  Map<String, Object?>? profile,
  Completer<void>? loadGate,
  Completer<void>? submitGate,
  Map<String, Completer<void>> operationGates = const {},
  bool loadFailure = false,
  bool settle = true,
}) async {
  final dependencies = configureDependencies(
    tokens: MemoryTokens(),
    camera: NoCaptureCamera(),
  );
  final user = {...userJson, 'role': role.apiValue};
  final currentProfile = profile ?? profileJson;
  dependencies<Dio>().httpClientAdapter = TestAdapter((options) async {
    final operationGate = operationGates[options.path];
    if (operationGate != null) await operationGate.future;
    if (options.path == '/kyc/submit' && submitGate != null) {
      await submitGate.future;
    }
    if (options.path == '/kyc') {
      if (loadGate != null) await loadGate.future;
      if (loadFailure) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      }
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
    return jsonResponse(switch (options.path) {
      '/auth/refresh' => {...sessionJson, 'user': user},
      '/auth/me' => {'user': user},
      '/access/role-request' => {'request': null},
      '/reviews/applicant' => {
        'submissionId': '00000000-0000-4000-8000-000000000001',
        'user': {'id': 'applicant', 'email': 'applicant@example.test'},
        'profile': {
          ...profileJson,
          'status': 'pending_review',
          'nextStep': 'result',
        },
      },
      '/kyc' => {'profile': currentProfile},
      '/kyc/submit' => {
        'profile': {
          ...currentProfile,
          'status': 'pending_review',
          'nextStep': 'result',
        },
      },
      '/kyc/personal-details' => {
        'profile': {...currentProfile, 'nextStep': 'document'},
      },
      '/kyc/resubmit' => {
        'profile': {
          ...currentProfile,
          'status': 'in_progress',
          'nextStep': 'document',
        },
      },
      '/reviews/applicant/decision' => {
        'profile': {...profileJson, 'status': 'verified', 'nextStep': 'result'},
      },
      _ => {
        'users': [],
        'requests': [],
        'profiles': [],
        'submissions': [],
        'total': 0,
      },
    });
  });
  addTearDown(() async {
    if (loadGate != null && !loadGate.isCompleted) loadGate.complete();
    if (submitGate != null && !submitGate.isCompleted) submitGate.complete();
    for (final gate in operationGates.values) {
      if (!gate.isCompleted) gate.complete();
    }
    await tester.pumpWidget(const SizedBox());
    await dependencies.reset();
  });
  await tester.pumpWidget(KycApp(dependencies: dependencies));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  final router =
      tester.widget<MaterialApp>(find.byType(MaterialApp)).routerConfig!
          as GoRouter;
  router.go(location);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }
  return (dependencies, router);
}

const profileJson = <String, Object?>{
  'id': 'profile-test',
  'status': 'in_progress',
  'nextStep': 'review',
  'personalDetails': {
    'fullName': 'Demo Applicant',
    'dateOfBirth': '1995-04-15',
    'nationality': 'Vietnamese',
    'address': '1 Demo Street',
    'documentNumber': 'DEMO1234',
  },
  'document': {
    'id': 'document',
    'mimeType': 'image/png',
    'size': 68,
    'documentType': 'passport',
  },
  'selfie': {'id': 'selfie', 'mimeType': 'image/png', 'size': 68},
};
