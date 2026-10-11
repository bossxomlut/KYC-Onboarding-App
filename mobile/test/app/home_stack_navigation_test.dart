import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/features/kyc/presentation/bloc/kyc_cubit.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/home_page.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/personal_details_page.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/review_page.dart';
import 'system_back_test.dart' show profileJson, pumpApp;

void main() {
  for (final useSystemBack in [false, true]) {
    testWidgets(
      'Home pushes KYC and ${useSystemBack ? 'system' : 'toolbar'} Back pops to the same Home',
      (tester) async {
        final (_, router) = await pumpApp(tester, location: '/');
        final home = tester.element(find.byType(HomePage));
        final cubit = home.read<KycCubit>();

        await tester.ensureVisible(find.byKey(const Key('kyc-next')));
        await tester.tap(find.byKey(const Key('kyc-next')));
        await tester.pumpAndSettle();

        expect(router.state.uri.path, '/kyc/review');
        expect(router.canPop(), isTrue);
        expect(home.mounted, isTrue);
        if (useSystemBack) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tap(find.byTooltip('Back'));
        }
        await tester.pumpAndSettle();

        expect(router.state.uri.path, '/');
        expect(router.canPop(), isFalse);
        expect(tester.element(find.byType(HomePage)), same(home));
        expect(home.read<KycCubit>(), same(cubit));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final entry in {
    'account-access': '/access',
    'view-kyc-history': '/kyc/history',
  }.entries) {
    testWidgets('repeated ${entry.key} visits preserve Home and its KYC flow', (
      tester,
    ) async {
      final (_, router) = await pumpApp(tester, location: '/');
      final home = tester.element(find.byType(HomePage));
      final cubit = home.read<KycCubit>();

      for (var visit = 0; visit < 3; visit++) {
        await tester.ensureVisible(find.byKey(Key(entry.key)));
        await tester.tap(find.byKey(Key(entry.key)));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, entry.value);
        expect(router.canPop(), isTrue);
        expect(home.mounted, isTrue);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(router.state.uri.path, '/');
        expect(router.canPop(), isFalse);
        expect(tester.element(find.byType(HomePage)), same(home));
        expect(home.read<KycCubit>(), same(cubit));
        expect(cubit.isClosed, isFalse);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('saving a KYC step retains the Home entry for Back', (
    tester,
  ) async {
    final (_, router) = await pumpApp(
      tester,
      location: '/',
      profile: {...profileJson, 'nextStep': 'personal_details'},
    );
    final home = tester.element(find.byType(HomePage));
    await tester.ensureVisible(find.byKey(const Key('kyc-next')));
    await tester.tap(find.byKey(const Key('kyc-next')));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/kyc/details');

    await tester.tap(find.byKey(const Key('save-details')));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/kyc/document');
    expect(router.canPop(), isTrue);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/');
    expect(tester.element(find.byType(HomePage)), same(home));
    expect(router.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('status history pops back to status, then Home', (tester) async {
    final (_, router) = await pumpApp(
      tester,
      location: '/',
      profile: {
        ...profileJson,
        'status': 'pending_review',
        'nextStep': 'result',
      },
    );
    final home = tester.element(find.byType(HomePage));
    await tester.ensureVisible(find.byKey(const Key('kyc-next')));
    await tester.tap(find.byKey(const Key('kyc-next')));
    await tester.pumpAndSettle();
    final cubit = home.read<KycCubit>();

    await tester.ensureVisible(find.byKey(const Key('view-kyc-history')));
    await tester.tap(find.byKey(const Key('view-kyc-history')));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/kyc/history');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/kyc/status');
    expect(cubit.isClosed, isFalse);

    await tester.ensureVisible(find.text('Back to home'));
    await tester.tap(find.text('Back to home'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/');
    expect(tester.element(find.byType(HomePage)), same(home));
    expect(router.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('submission keeps the original Home below verification status', (
    tester,
  ) async {
    final (_, router) = await pumpApp(tester, location: '/');
    final home = tester.element(find.byType(HomePage));
    await tester.ensureVisible(find.byKey(const Key('kyc-next')));
    await tester.tap(find.byKey(const Key('kyc-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('submit-kyc')));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/kyc/status');
    expect(router.canPop(), isTrue);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/');
    expect(tester.element(find.byType(HomePage)), same(home));
    expect(router.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'iOS edge swipe pops the feature back to Home',
    (tester) async {
      final (_, router) = await pumpApp(tester, location: '/');
      final home = tester.element(find.byType(HomePage));
      await tester.ensureVisible(find.byKey(const Key('kyc-next')));
      await tester.tap(find.byKey(const Key('kyc-next')));
      await tester.pumpAndSettle();
      final route = ModalRoute.of(tester.element(find.byType(ReviewPage)))!;
      expect(route.popGestureEnabled, isTrue);

      await tester.dragFrom(const Offset(0, 300), const Offset(700, 0));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/');
      expect(tester.element(find.byType(HomePage)), same(home));
      expect(router.canPop(), isFalse);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets('a popped save cannot navigate a new visit to the same page', (
    tester,
  ) async {
    final gate = Completer<void>();
    final (_, router) = await pumpApp(
      tester,
      location: '/',
      profile: {...profileJson, 'nextStep': 'personal_details'},
      operationGates: {'/kyc/personal-details': gate},
    );
    await tester.ensureVisible(find.byKey(const Key('kyc-next')));
    await tester.tap(find.byKey(const Key('kyc-next')));
    await tester.pumpAndSettle();
    final oldPage = tester.element(find.byType(PersonalDetailsPage));
    await tester.tap(find.byKey(const Key('save-details')));
    await tester.pump();
    router.pop();
    await tester.pump();
    router.push<void>('/kyc/details');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(oldPage.mounted, isTrue);
    expect(router.state.uri.path, '/kyc/details');

    gate.complete();
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/kyc/details');
    expect(tester.takeException(), isNull);
  });
}
