import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kyc_onboarding/core/domain/result.dart';
import 'package:kyc_onboarding/features/access/domain/entities/access_entities.dart';
import 'package:kyc_onboarding/features/access/domain/usecases/access_usecases.dart';
import 'package:kyc_onboarding/features/access/presentation/bloc/access_cubit.dart';
import 'package:kyc_onboarding/features/access/presentation/pages/reviewer_queue_page.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';
import 'package:kyc_onboarding/features/kyc/presentation/widgets/kyc_status_badge.dart';

import 'access_cubit_test.dart';

void main() {
  testWidgets('search and review filters fit a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mountQueue(
      tester,
      _QueueRepository(
        items: [
          _profile(email: 'a.very.long.email.for.a.narrow.screen@example.test'),
        ],
      ),
    );

    expect(find.widgetWithText(TextField, 'Search by email'), findsOneWidget);
    for (final filter in ['pending', 'approved', 'rejected', 'all']) {
      expect(find.byKey(Key('review-filter-$filter')), findsOneWidget);
    }
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('review-search')))
          .maxLength,
      254,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('review-filter-pending')))
          .selected,
      isTrue,
    );
    expect(find.byType(KycStatusBadge), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search debounces typing and clear applies immediately', (
    tester,
  ) async {
    final repository = _QueueRepository();
    final cubit = await _mountQueue(tester, repository);
    repository.calls.clear();

    await tester.enterText(find.byKey(const Key('review-search')), 'ali');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byKey(const Key('review-search')), 'alice');
    await tester.pump(const Duration(milliseconds: 349));
    expect(repository.calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(repository.calls, [
      (offset: 0, filter: ReviewFilter.pending, search: 'alice'),
    ]);
    expect(cubit.state.reviewSearch, 'alice');

    await tester.enterText(
      find.byKey(const Key('review-search')),
      'unfinished',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(repository.calls.last.search, isEmpty);
    expect(cubit.state.reviewSearch, isEmpty);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('review-search')))
          .controller!
          .text,
      isEmpty,
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(repository.calls, hasLength(2));
  });

  testWidgets('changing a filter includes the search draft and resets paging', (
    tester,
  ) async {
    final repository = _QueueRepository();
    final cubit = await _mountQueue(tester, repository, offset: 50);
    repository.calls.clear();
    await tester.enterText(find.byKey(const Key('review-search')), 'alice');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('review-filter-approved')));
    await tester.pumpAndSettle();

    expect(repository.calls, [
      (offset: 0, filter: ReviewFilter.approved, search: 'alice'),
    ]);
    expect(cubit.state.queue!.offset, 0);
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('review-filter-approved')))
          .selected,
      isTrue,
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(repository.calls, hasLength(1));
  });

  testWidgets('pagination and refresh retain the active search and filter', (
    tester,
  ) async {
    final repository = _QueueRepository(
      items: [
        _profile(userId: 'first'),
        _profile(userId: 'second'),
      ],
      total: 101,
    );
    await _mountQueue(
      tester,
      repository,
      offset: 50,
      filter: ReviewFilter.approved,
      search: 'alice',
    );
    repository.calls.clear();
    expect(find.text('51–52 of 101'), findsOneWidget);
    await tester.ensureVisible(find.text('Next'));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(repository.calls.last, (
      offset: 52,
      filter: ReviewFilter.approved,
      search: 'alice',
    ));
    expect(find.text('53–54 of 101'), findsOneWidget);
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(repository.calls.last, (
      offset: 52,
      filter: ReviewFilter.approved,
      search: 'alice',
    ));
    await tester.ensureVisible(find.text('Previous'));
    await tester.tap(find.text('Previous'));
    await tester.pumpAndSettle();
    expect(repository.calls.last, (
      offset: 2,
      filter: ReviewFilter.approved,
      search: 'alice',
    ));
  });

  testWidgets('empty results describe the active filter or search', (
    tester,
  ) async {
    await _mountQueue(tester, _QueueRepository());
    expect(find.text('No profiles are waiting for review.'), findsOneWidget);
    for (final entry in {
      'approved': 'No approved profiles.',
      'rejected': 'No rejected profiles.',
      'all': 'No submitted profiles.',
    }.entries) {
      await tester.tap(find.byKey(Key('review-filter-${entry.key}')));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      expect(find.text('0 items'), findsOneWidget);
    }
    await tester.enterText(find.byKey(const Key('review-search')), 'missing');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('No profiles match your search.'), findsOneWidget);
  });

  for (final status in [
    KycStatus.pendingReview,
    KycStatus.verified,
    KycStatus.rejected,
  ]) {
    testWidgets(
      '${status.name} opens its route and preserves queue on return',
      (tester) async {
        const userId = 'target/user';
        final repository = _QueueRepository(
          items: [_profile(userId: userId, status: status)],
          total: 1,
        );
        final cubit = AccessCubit(AccessUseCases(repository));
        await cubit.loadQueue(filter: ReviewFilter.all, search: 'sample');
        Uri? openedUri;
        String? openedUserId;
        final router = GoRouter(
          initialLocation: '/reviews',
          routes: [
            GoRoute(
              path: '/reviews',
              builder: (_, _) => const ReviewerQueuePage(actorId: 'reviewer'),
            ),
            GoRoute(
              path: '/reviews/:userId',
              builder: (_, state) {
                openedUri = state.uri;
                openedUserId = state.pathParameters['userId'];
                return const Scaffold(body: Text('Pending detail'));
              },
            ),
            GoRoute(
              path: '/reviews/:userId/history',
              builder: (_, state) {
                openedUri = state.uri;
                openedUserId = state.pathParameters['userId'];
                return const Scaffold(body: Text('Read-only history'));
              },
            ),
          ],
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          router.dispose();
          await cubit.close();
        });
        await tester.pumpWidget(
          BlocProvider.value(
            value: cubit,
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<KycStatusBadge>(find.byType(KycStatusBadge)).status,
          status,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('review-profile-$userId')),
        );
        await tester.tap(find.byKey(const ValueKey('review-profile-$userId')));
        await tester.pumpAndSettle();
        final isPending = status == KycStatus.pendingReview;
        expect(
          find.text(isPending ? 'Pending detail' : 'Read-only history'),
          findsOneWidget,
        );
        expect(
          openedUri.toString(),
          isPending
              ? '/reviews/target%2Fuser'
              : '/reviews/target%2Fuser/history?from=queue',
        );
        expect(openedUserId, userId);

        router.pop();
        await tester.pumpAndSettle();
        expect(find.byType(ReviewerQueuePage), findsOneWidget);
        expect(
          tester
              .widget<ChoiceChip>(find.byKey(const Key('review-filter-all')))
              .selected,
          isTrue,
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('review-search')))
              .controller!
              .text,
          'sample',
        );
        expect(repository.calls.last, (
          offset: 0,
          filter: ReviewFilter.all,
          search: 'sample',
        ));
        expect(repository.calls, hasLength(2));
      },
    );
  }

  testWidgets('own profile cannot be opened', (tester) async {
    await _mountQueue(
      tester,
      _QueueRepository(items: [_profile(userId: 'reviewer')], total: 1),
    );
    expect(tester.widget<ListTile>(find.byType(ListTile)).enabled, isFalse);
  });

  testWidgets('leaving the queue cancels a pending search', (tester) async {
    final repository = _QueueRepository();
    await _mountQueue(tester, repository);
    repository.calls.clear();
    await tester.enterText(find.byKey(const Key('review-search')), 'alice');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 400));
    expect(repository.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

Future<AccessCubit> _mountQueue(
  WidgetTester tester,
  _QueueRepository repository, {
  int offset = 0,
  ReviewFilter filter = ReviewFilter.pending,
  String search = '',
}) async {
  final cubit = AccessCubit(AccessUseCases(repository));
  await cubit.loadQueue(filter: filter, search: search);
  if (offset != 0) await cubit.loadQueue(offset: offset);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await cubit.close();
  });
  await tester.pumpWidget(
    BlocProvider.value(
      value: cubit,
      child: const MaterialApp(home: ReviewerQueuePage(actorId: 'reviewer')),
    ),
  );
  return cubit;
}

ReviewSummary _profile({
  String userId = 'target',
  String email = 'sample@example.test',
  KycStatus status = KycStatus.pendingReview,
}) => ReviewSummary(
  userId: userId,
  email: email,
  submittedAt: DateTime.utc(2026, 10, 10, 8),
  status: status,
);

class _QueueRepository extends FakeAccessRepository {
  _QueueRepository({this.items = const [], this.total = 0});
  final List<ReviewSummary> items;
  final int total;
  final calls = <({int offset, ReviewFilter filter, String search})>[];

  @override
  Future<Result<PageResult<ReviewSummary>>> reviewQueue({
    int offset = 0,
    ReviewFilter filter = ReviewFilter.pending,
    String search = '',
  }) async {
    calls.add((offset: offset, filter: filter, search: search));
    return Success(PageResult(items: items, total: total, offset: offset));
  }
}
