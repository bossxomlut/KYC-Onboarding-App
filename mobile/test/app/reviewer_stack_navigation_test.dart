import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:kyc_onboarding/features/access/presentation/bloc/access_cubit.dart';
import 'package:kyc_onboarding/features/access/presentation/pages/access_page.dart';
import 'package:kyc_onboarding/features/access/presentation/pages/admin_home_page.dart';
import 'package:kyc_onboarding/features/access/presentation/pages/reviewer_detail_page.dart';
import 'package:kyc_onboarding/features/access/presentation/pages/reviewer_queue_page.dart';
import 'package:kyc_onboarding/features/auth/domain/entities/user.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/home_page.dart';

import '../features/auth/data/session_restore_test.dart'
    show TestAdapter, jsonResponse, userJson;
import 'system_back_test.dart' show profileJson, pumpApp;

void main() {
  for (final withDetail in [false, true]) {
    testWidgets(
      'revoked reviewer access removes pushed ${withDetail ? 'private detail and dialog' : 'queue'}',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final (dependencies, router) = await pumpApp(
          tester,
          location: '/',
          role: UserRole.reviewer,
        );
        final dio = dependencies<Dio>();
        final original = dio.httpClientAdapter;
        var role = 'reviewer';
        dio.httpClientAdapter = TestAdapter((options) async {
          if (options.path == '/auth/me') {
            return jsonResponse({
              'user': {...userJson, 'role': role},
            });
          }
          return original.fetch(options, null, null);
        });
        await tester.ensureVisible(find.byKey(const Key('review-profiles')));
        await tester.tap(find.byKey(const Key('review-profiles')));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, '/reviews');
        if (withDetail) {
          router.push<void>('/reviews/applicant');
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byKey(const Key('review-approve')));
          await tester.tap(find.byKey(const Key('review-approve')));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
        }

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        role = 'user';
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();

        expect(router.state.uri.path, '/access');
        expect(find.byType(AccessPage), findsOneWidget);
        expect(find.byType(ReviewerQueuePage), findsNothing);
        expect(find.byType(ReviewerDetailPage), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final action in ['manage-accounts', 'review-profiles']) {
    testWidgets('admin Home pushes $action and toolbar Back restores Home', (
      tester,
    ) async {
      final (_, router) = await pumpApp(
        tester,
        location: '/',
        role: UserRole.superAdmin,
      );
      final home = tester.element(find.byType(AdminHomePage));
      await tester.tap(find.byKey(Key(action)));
      await tester.pumpAndSettle();
      expect(router.canPop(), isTrue);
      expect(home.mounted, isTrue);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/');
      expect(tester.element(find.byType(AdminHomePage)), same(home));
      expect(router.canPop(), isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('review queue opened from account access pops back to access', (
    tester,
  ) async {
    final (_, router) = await pumpApp(
      tester,
      location: '/',
      role: UserRole.reviewer,
    );
    router.push<void>('/access');
    await tester.pumpAndSettle();
    final access = tester.element(find.byType(AccessPage));
    final cubit = access.read<AccessCubit>();
    await tester.ensureVisible(find.text('Review profiles'));
    await tester.tap(find.text('Review profiles'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/reviews');

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/access');
    expect(
      tester.element(find.byType(AccessPage)).read<AccessCubit>(),
      same(cubit),
    );
    expect(cubit.isClosed, isFalse);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/');
    expect(find.byType(HomePage), findsOneWidget);
    expect(router.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('review history Back restores detail then the retained queue', (
    tester,
  ) async {
    final (dependencies, router) = await pumpApp(
      tester,
      location: '/',
      role: UserRole.reviewer,
    );
    final api = _QueueApi(dependencies);
    router.push<void>('/reviews');
    await tester.pumpAndSettle();
    final queue = tester.element(find.byType(ReviewerQueuePage));
    final cubit = queue.read<AccessCubit>();
    final loading = cubit.loadQueue(offset: 50);
    await tester.pumpAndSettle();
    await loading;
    await tester.tap(find.text('applicant@example.test'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/reviews/applicant');
    final detail = tester.element(find.byType(ReviewerDetailPage));
    final detailCubit = detail.read<AccessCubit>();
    expect(find.text('Back to review queue'), findsNothing);
    expect(find.byTooltip('Back'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('view-applicant-history')));
    await tester.tap(find.byKey(const Key('view-applicant-history')));
    await tester.pumpAndSettle();

    expect(find.text('Back to review queue'), findsNothing);
    expect(find.text('Back to current review'), findsNothing);
    expect(find.byTooltip('Back'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/reviews/applicant');
    expect(
      tester.element(find.byType(ReviewerDetailPage)).read<AccessCubit>(),
      same(detailCubit),
    );
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/reviews');
    expect(
      tester.element(find.byType(ReviewerQueuePage)).read<AccessCubit>(),
      same(cubit),
    );
    expect(cubit.state.queue!.offset, 50);
    expect(api.queueOffsets, [0, 50, 50]);
    expect(detailCubit.isClosed, isTrue);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/');
    expect(router.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final approve in [true, false]) {
    testWidgets(
      '${approve ? 'approval' : 'rejection'} pops detail and refreshes the same queue page',
      (tester) async {
        final (dependencies, router) = await pumpApp(
          tester,
          location: '/',
          role: UserRole.reviewer,
        );
        final api = _QueueApi(dependencies);
        router.push<void>('/reviews');
        await tester.pumpAndSettle();
        final queue = tester.element(find.byType(ReviewerQueuePage));
        final cubit = queue.read<AccessCubit>();
        final loading = cubit.loadQueue(offset: 50);
        await tester.pumpAndSettle();
        await loading;
        await tester.tap(find.text('applicant@example.test'));
        await tester.pumpAndSettle();
        final detailCubit = tester
            .element(find.byType(ReviewerDetailPage))
            .read<AccessCubit>();
        final decision = find.byKey(
          Key(approve ? 'review-approve' : 'review-reject'),
        );
        await tester.ensureVisible(decision);
        await tester.tap(decision);
        await tester.pumpAndSettle();
        if (!approve) {
          await tester.enterText(
            find.byKey(const Key('rejection-reason')),
            'Please retake the selfie.',
          );
          await tester.tap(find.widgetWithText(CheckboxListTile, 'Selfie'));
        }
        await tester.tap(find.text(approve ? 'Approve' : 'Save rejection'));
        await tester.pumpAndSettle();

        expect(router.state.uri.path, '/reviews');
        expect(
          tester.element(find.byType(ReviewerQueuePage)).read<AccessCubit>(),
          same(cubit),
        );
        expect(cubit.state.queue!.offset, 50);
        expect(cubit.state.queue!.items, isEmpty);
        expect(api.queueOffsets, [0, 50, 50]);
        expect(api.decisions, 1);
        expect(detailCubit.isClosed, isTrue);
        expect(router.canPop(), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'deep-linked review detail returns to its queue without a stack',
    (tester) async {
      final (_, router) = await pumpApp(
        tester,
        location: '/reviews/applicant',
        role: UserRole.reviewer,
      );
      expect(router.canPop(), isFalse);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/reviews');
      expect(find.byType(ReviewerQueuePage), findsOneWidget);
      expect(router.canPop(), isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}

class _QueueApi {
  _QueueApi(GetIt dependencies) {
    final dio = dependencies<Dio>();
    final original = dio.httpClientAdapter;
    dio.httpClientAdapter = TestAdapter((options) async {
      if (options.path.split('?').first == '/reviews') {
        queueOffsets.add(
          int.parse(Uri.parse(options.path).queryParameters['offset'] ?? '0'),
        );
        return jsonResponse({
          'profiles': [
            if (decisions == 0)
              {
                'userId': 'applicant',
                'email': 'applicant@example.test',
                'status': 'pending_review',
                'submittedAt': null,
              },
          ],
          'total': decisions == 0 ? 100 : 99,
        });
      }
      if (options.path == '/reviews/applicant/decision') {
        decisions++;
        return jsonResponse({
          'profile': {
            ...profileJson,
            'status': 'verified',
            'nextStep': 'result',
          },
        });
      }
      return original.fetch(options, null, null);
    });
  }

  final queueOffsets = <int>[];
  int decisions = 0;
}
