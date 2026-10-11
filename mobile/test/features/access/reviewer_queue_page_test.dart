import 'dart:async';

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

  testWidgets('search keeps its focus, keyboard and selection while loading', (
    tester,
  ) async {
    final repository = _QueueRepository();
    final cubit = await _mountQueue(tester, repository);
    _deferQueueResponses(repository);
    final search = find.byKey(const Key('review-search'));
    final editable = find.descendant(
      of: search,
      matching: find.byType(EditableText),
    );
    await tester.showKeyboard(search);
    const value = TextEditingValue(
      text: 'alice@example.test',
      selection: TextSelection(baseOffset: 2, extentOffset: 5),
    );
    tester.testTextInput.updateEditingValue(value);
    await tester.pump();
    final original = tester.state<EditableTextState>(editable);
    expect(original.widget.focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(cubit.state.busy, isTrue);
    expect(
      tester.state<EditableTextState>(editable).widget.focusNode.hasFocus,
      isTrue,
      reason: 'Starting a debounced search must keep the active input focused.',
    );
    expect(tester.state<EditableTextState>(editable), same(original));
    expect(tester.testTextInput.isVisible, isTrue);
    expect(tester.testTextInput.hasAnyClients, isTrue);
    expect(original.widget.controller.value, value);

    repository.responseGates.single.complete(_emptyQueueResult);
    await tester.pumpAndSettle();
    expect(cubit.state.busy, isFalse);
    expect(tester.state<EditableTextState>(editable), same(original));
    expect(original.widget.focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(original.widget.controller.value, value);
  });

  testWidgets('search stays in place while its delayed results load', (
    tester,
  ) async {
    final repository = _QueueRepository();
    await _mountQueue(tester, repository);
    _deferQueueResponses(repository);
    final search = find.byKey(const Key('review-search'));
    await tester.enterText(search, 'alice');
    final originalRect = tester.getRect(search);

    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(
      tester.getRect(search),
      originalRect,
      reason: 'Loading feedback must not push the search field down.',
    );
    repository.responseGates.single.complete(_emptyQueueResult);
    await tester.pumpAndSettle();
    expect(tester.getRect(search), originalRect);
  });

  testWidgets('scrolled narrow search stays steady with the keyboard open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final repository = _QueueRepository(
      items: List.generate(20, (index) => _profile(userId: 'applicant-$index')),
      total: 20,
    );
    final cubit = await _mountQueue(tester, repository);
    _deferQueueResponses(repository);
    final search = find.byKey(const Key('review-search'));
    final scrollable = tester.state<ScrollableState>(
      find.ancestor(of: search, matching: find.byType(Scrollable)),
    );
    final offsetToSearch =
        scrollable.position.pixels +
        tester.getRect(search).top -
        (kToolbarHeight + 20);
    scrollable.position.jumpTo(
      offsetToSearch.clamp(
        scrollable.position.minScrollExtent,
        scrollable.position.maxScrollExtent,
      ),
    );
    await tester.pumpAndSettle();
    await tester.showKeyboard(search);
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, greaterThan(0));
    const value = TextEditingValue(
      text: 'alice@example.test',
      selection: TextSelection(baseOffset: 2, extentOffset: 5),
    );
    tester.testTextInput.updateEditingValue(value);
    await tester.pump();
    final originalRect = tester.getRect(search);
    final originalOffset = scrollable.position.pixels;
    final originalMaxScroll = scrollable.position.maxScrollExtent;
    expect(originalRect.top, closeTo(kToolbarHeight + 20, 0.1));
    expect(originalRect.top, greaterThanOrEqualTo(kToolbarHeight));
    expect(originalRect.bottom, lessThanOrEqualTo(400));

    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(cubit.state.busy, isTrue);
    expect(
      tester.getRect(search),
      originalRect,
      reason:
          'Clearing results must not clamp the scroll offset while typing. '
          'Before: offset=$originalOffset, max=$originalMaxScroll. '
          'Loading: offset=${scrollable.position.pixels}, '
          'max=${scrollable.position.maxScrollExtent}.',
    );
    expect(tester.widget<TextField>(search).controller!.value, value);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(tester.testTextInput.hasAnyClients, isTrue);
    expect(tester.takeException(), isNull);
    repository.responseGates.single.complete(_emptyQueueResult);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(search),
      originalRect,
      reason:
          'Empty results must keep the visible search in place. '
          'Before: offset=$originalOffset, max=$originalMaxScroll. '
          'After: offset=${scrollable.position.pixels}, '
          'max=${scrollable.position.maxScrollExtent}.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('typing continues through pending and trailing search requests', (
    tester,
  ) async {
    final repository = _QueueRepository();
    final cubit = await _mountQueue(tester, repository);
    repository.calls.clear();
    _deferQueueResponses(repository);
    final search = find.byKey(const Key('review-search'));
    await tester.showKeyboard(search);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'alice',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(cubit.state.busy, isTrue);
    expect(
      tester.testTextInput.hasAnyClients,
      isTrue,
      reason: 'The keyboard must stay connected while a request is pending.',
    );

    const latestValue = TextEditingValue(
      text: 'alice@example.test',
      selection: TextSelection.collapsed(offset: 18),
    );
    tester.testTextInput.updateEditingValue(latestValue);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(repository.calls.single.search, 'alice');
    expect(tester.widget<TextField>(search).controller!.value, latestValue);

    repository.responseGates.first.complete(_emptyQueueResult);
    await tester.pump();
    await tester.pump();
    expect(repository.calls.map((call) => call.search), [
      'alice',
      'alice@example.test',
    ]);
    expect(repository.responseGates, hasLength(2));
    expect(cubit.state.busy, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(tester.testTextInput.hasAnyClients, isTrue);
    repository.responseGates.last.complete(_emptyQueueResult);
    await tester.pumpAndSettle();
    expect(cubit.state.reviewSearch, 'alice@example.test');
    expect(tester.widget<TextField>(search).controller!.value, latestValue);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(tester.testTextInput.hasAnyClients, isTrue);
  });

  testWidgets('search focus and position survive a failed request and retry', (
    tester,
  ) async {
    final repository = _QueueRepository();
    final cubit = await _mountQueue(tester, repository);
    _deferQueueResponses(repository);
    final search = find.byKey(const Key('review-search'));
    final editable = find.descendant(
      of: search,
      matching: find.byType(EditableText),
    );
    await tester.showKeyboard(search);
    const value = TextEditingValue(
      text: 'alice@example.test',
      selection: TextSelection(baseOffset: 1, extentOffset: 4),
    );
    tester.testTextInput.updateEditingValue(value);
    await tester.pump();
    final original = tester.state<EditableTextState>(editable);
    final originalRect = tester.getRect(search);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    repository.responseGates.single.complete(
      const Failure(
        AppFailure(code: 'NETWORK_ERROR', message: 'Search could not refresh.'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Search could not refresh.'), findsOneWidget);
    expect(tester.getRect(search), originalRect);
    expect(tester.state<EditableTextState>(editable), same(original));
    expect(original.widget.focusNode.hasFocus, isTrue);
    expect(original.widget.controller.value, value);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pump();
    expect(cubit.state.busy, isTrue);
    expect(tester.getRect(search), originalRect);
    expect(tester.state<EditableTextState>(editable), same(original));
    expect(original.widget.focusNode.hasFocus, isTrue);
    expect(original.widget.controller.value, value);
    expect(tester.testTextInput.isVisible, isTrue);
    repository.responseGates.last.complete(_emptyQueueResult);
    await tester.pumpAndSettle();
    expect(cubit.state.error, isNull);
    expect(tester.getRect(search), originalRect);
    expect(tester.state<EditableTextState>(editable), same(original));
    expect(original.widget.focusNode.hasFocus, isTrue);
    expect(original.widget.controller.value, value);
    expect(tester.testTextInput.isVisible, isTrue);
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
  bool deferResponses = false;
  final responseGates = <Completer<Result<PageResult<ReviewSummary>>>>[];

  @override
  Future<Result<PageResult<ReviewSummary>>> reviewQueue({
    int offset = 0,
    ReviewFilter filter = ReviewFilter.pending,
    String search = '',
  }) async {
    calls.add((offset: offset, filter: filter, search: search));
    if (deferResponses) {
      final response = Completer<Result<PageResult<ReviewSummary>>>();
      responseGates.add(response);
      return response.future;
    }
    return Success(PageResult(items: items, total: total, offset: offset));
  }
}

const _emptyQueueResult = Success(
  PageResult<ReviewSummary>(items: [], total: 0, offset: 0),
);

void _deferQueueResponses(_QueueRepository repository) {
  repository.deferResponses = true;
  addTearDown(() {
    for (final gate in repository.responseGates) {
      if (!gate.isCompleted) gate.complete(_emptyQueueResult);
    }
  });
}
