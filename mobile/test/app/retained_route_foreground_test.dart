import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:kyc_onboarding/features/access/presentation/bloc/access_cubit.dart';
import 'package:kyc_onboarding/features/access/presentation/pages/reviewer_detail_page.dart';
import 'package:kyc_onboarding/features/auth/domain/entities/user.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';
import 'package:kyc_onboarding/features/kyc/presentation/bloc/kyc_cubit.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/home_page.dart';
import '../features/auth/data/session_restore_test.dart'
    show TestAdapter, jsonResponse;
import 'system_back_test.dart' show profileJson, pumpApp;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

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
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('Home reconciles after a resumed history page is popped', (
    tester,
  ) async {
    final (dependencies, router) = await pumpApp(tester, location: '/');
    final api = _RetainedRouteApi(dependencies);
    final home = tester.element(find.byType(HomePage));
    final cubit = home.read<KycCubit>();
    router.push<void>('/kyc/history');
    await tester.pumpAndSettle();
    api.calls.clear();

    await background(tester);
    api.profile = {...profileJson, 'status': 'verified', 'nextStep': 'result'};
    await resume(tester);
    await tester.pumpAndSettle();
    expect(api.calls, ['/auth/me', '/kyc/history']);
    expect(cubit.state.profile!.status, KycStatus.inProgress);

    api.calls.clear();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/');
    expect(tester.element(find.byType(HomePage)), same(home));
    expect(home.read<KycCubit>(), same(cubit));
    expect(cubit.state.profile!.status, KycStatus.verified);
    expect(api.calls, ['/auth/me', '/kyc']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'retained review detail blocks decisions until revealed refresh',
    (tester) async {
      final (dependencies, router) = await pumpApp(
        tester,
        location: '/',
        role: UserRole.reviewer,
      );
      final api = _RetainedRouteApi(dependencies);
      router.push<void>('/reviews/applicant');
      await tester.pumpAndSettle();
      final detail = tester.element(find.byType(ReviewerDetailPage));
      final cubit = detail.read<AccessCubit>();
      router.push<void>('/reviews/applicant/history');
      await tester.pumpAndSettle();
      api.calls.clear();

      await background(tester);
      expect(cubit.state.needsRevalidation, isTrue);
      await resume(tester);
      await tester.pumpAndSettle();
      expect(api.calls, ['/auth/me', '/reviews/applicant/history']);
      expect(cubit.state.needsRevalidation, isTrue);

      api.calls.clear();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/reviews/applicant');
      expect(tester.element(find.byType(ReviewerDetailPage)), same(detail));
      expect(cubit.state.needsRevalidation, isFalse);
      expect(api.calls.first, '/auth/me');
      expect(
        api.calls.where((path) => path == '/reviews/applicant'),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ordinary push and pop do not refresh retained Home', (
    tester,
  ) async {
    final (dependencies, router) = await pumpApp(tester, location: '/');
    final api = _RetainedRouteApi(dependencies);
    final home = tester.element(find.byType(HomePage));
    router.push<void>('/kyc/history');
    await tester.pumpAndSettle();
    api.calls.clear();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(api.calls, isEmpty);
    expect(tester.element(find.byType(HomePage)), same(home));
    expect(tester.takeException(), isNull);
  });

  testWidgets('pushed KYC route resume performs one session and profile read', (
    tester,
  ) async {
    final (dependencies, router) = await pumpApp(tester, location: '/');
    final api = _RetainedRouteApi(dependencies);
    router.push<void>('/kyc/details');
    await tester.pumpAndSettle();
    api.calls.clear();

    await background(tester);
    await resume(tester);
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/kyc/details');
    expect(api.calls, ['/auth/me', '/kyc']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Back during session revalidation refreshes revealed Home once', (
    tester,
  ) async {
    final (dependencies, router) = await pumpApp(tester, location: '/');
    final api = _RetainedRouteApi(dependencies);
    final cubit = tester.element(find.byType(HomePage)).read<KycCubit>();
    router.push<void>('/kyc/history');
    await tester.pumpAndSettle();
    api.calls.clear();
    api.meGate = Completer<void>();

    await background(tester);
    api.profile = {...profileJson, 'status': 'verified', 'nextStep': 'result'};
    await resume(tester);
    expect(api.calls, ['/auth/me']);
    await tester.binding.handlePopRoute();
    await tester.pump();
    api.meGate!.complete();
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/');
    expect(cubit.state.profile!.status, KycStatus.verified);
    expect(api.calls, ['/auth/me', '/kyc']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving during refresh keeps the route stale for later reveal', (
    tester,
  ) async {
    final (dependencies, router) = await pumpApp(
      tester,
      location: '/',
      role: UserRole.reviewer,
    );
    final api = _RetainedRouteApi(dependencies);
    router.push<void>('/reviews/applicant');
    await tester.pumpAndSettle();
    final detail = tester.element(find.byType(ReviewerDetailPage));
    final cubit = detail.read<AccessCubit>();
    api.calls.clear();
    api.meGate = Completer<void>();
    await background(tester);
    await resume(tester);
    expect(api.calls, ['/auth/me']);

    router.push<void>('/reviews/applicant/history');
    await tester.pump();
    api.meGate!.complete();
    await tester.pumpAndSettle();
    expect(cubit.state.needsRevalidation, isTrue);
    api.calls.clear();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(tester.element(find.byType(ReviewerDetailPage)), same(detail));
    expect(cubit.state.needsRevalidation, isFalse);
    expect(api.calls.first, '/auth/me');
    expect(
      api.calls.where((path) => path == '/reviews/applicant'),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
  });
}

class _RetainedRouteApi {
  _RetainedRouteApi(GetIt dependencies) {
    final dio = dependencies<Dio>();
    final original = dio.httpClientAdapter;
    dio.httpClientAdapter = TestAdapter((options) async {
      calls.add(Uri.parse(options.path).path);
      if (options.path == '/auth/me' && meGate != null) {
        await meGate!.future;
      }
      if (options.path == '/kyc') return jsonResponse({'profile': profile});
      return original.fetch(options, null, null);
    });
    addTearDown(() {
      if (meGate != null && !meGate!.isCompleted) meGate!.complete();
    });
  }

  final calls = <String>[];
  Map<String, Object?> profile = {...profileJson};
  Completer<void>? meGate;
}
