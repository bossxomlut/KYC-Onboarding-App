import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/core/domain/result.dart';
import 'package:kyc_onboarding/features/access/domain/entities/access_entities.dart';
import 'package:kyc_onboarding/features/access/domain/repositories/access_repository.dart';
import 'package:kyc_onboarding/features/access/domain/usecases/access_usecases.dart';
import 'package:kyc_onboarding/features/access/presentation/bloc/access_cubit.dart';

class _QueueRepository implements AccessRepository {
  final queueRequests = <({int offset, ReviewFilter filter, String search})>[];
  final gates = <Completer<void>>[];
  bool deferred = false;
  int total = 101;
  AppFailure? failure;

  @override
  Future<Result<PageResult<ReviewSummary>>> reviewQueue({
    int offset = 0,
    ReviewFilter filter = ReviewFilter.pending,
    String search = '',
  }) async {
    queueRequests.add((offset: offset, filter: filter, search: search));
    if (deferred) {
      final gate = Completer<void>();
      gates.add(gate);
      await gate.future;
    }
    if (failure != null) return Failure(failure!);
    return Success(
      PageResult(
        items: offset >= total
            ? const []
            : [ReviewSummary(userId: 'u', email: search, submittedAt: null)],
        total: total,
        offset: offset,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('refresh keeps the current review-list page', () async {
    final repository = _QueueRepository();
    final cubit = AccessCubit(AccessUseCases(repository));
    addTearDown(cubit.close);

    await cubit.loadQueue(offset: 50);
    await cubit.loadQueue();

    expect(repository.queueRequests.map((request) => request.offset), [50, 50]);
    expect(cubit.state.queue?.offset, 50);
  });

  test('filter and search combine across pagination and refresh', () async {
    final repository = _QueueRepository();
    final cubit = AccessCubit(AccessUseCases(repository));
    addTearDown(cubit.close);

    await cubit.loadQueue(
      filter: ReviewFilter.approved,
      search: '  Applicant  ',
    );
    await cubit.loadQueue(offset: 50);
    await cubit.loadQueue();

    expect(repository.queueRequests, [
      (offset: 0, filter: ReviewFilter.approved, search: 'Applicant'),
      (offset: 50, filter: ReviewFilter.approved, search: 'Applicant'),
      (offset: 50, filter: ReviewFilter.approved, search: 'Applicant'),
    ]);
    expect(cubit.state.reviewFilter, ReviewFilter.approved);
    expect(cubit.state.reviewSearch, 'Applicant');
  });

  test(
    'changing criteria resets pagination but trimming alone does not',
    () async {
      final repository = _QueueRepository();
      final cubit = AccessCubit(AccessUseCases(repository));
      addTearDown(cubit.close);

      await cubit.loadQueue(search: 'applicant');
      await cubit.loadQueue(offset: 50);
      await cubit.loadQueue(search: ' applicant ');
      expect(cubit.state.queue?.offset, 50);
      await cubit.loadQueue(filter: ReviewFilter.approved, offset: 50);
      expect(cubit.state.queue?.offset, 0);
      await cubit.loadQueue(offset: 50);
      await cubit.loadQueue(search: '');
      expect(cubit.state.queue?.offset, 0);
      expect(repository.queueRequests.last.search, '');
      expect(repository.queueRequests.last.filter, ReviewFilter.approved);
    },
  );

  test(
    'latest criteria replace queued reads and discard old results',
    () async {
      final repository = _QueueRepository()..deferred = true;
      final cubit = AccessCubit(AccessUseCases(repository));
      addTearDown(cubit.close);

      final initial = cubit.loadQueue();
      final middle = cubit.loadQueue(
        filter: ReviewFilter.approved,
        search: 'old',
      );
      final latest = cubit.loadQueue(
        filter: ReviewFilter.rejected,
        search: 'new',
      );
      expect(cubit.state.reviewFilter, ReviewFilter.rejected);
      expect(cubit.state.reviewSearch, 'new');
      expect(cubit.state.queue, isNull);
      expect(repository.queueRequests.length, 1);

      repository.gates[0].complete();
      await Future<void>.delayed(Duration.zero);
      expect(repository.queueRequests.length, 2);
      expect(repository.queueRequests.last.filter, ReviewFilter.rejected);
      expect(repository.queueRequests.last.search, 'new');
      expect(cubit.state.queue, isNull);

      repository.gates[1].complete();
      await Future.wait([initial, middle, latest]);
      expect(cubit.state.queue?.items.single.email, 'new');
      expect(cubit.state.busy, isFalse);
    },
  );

  test('changing criteria clears previous rows before the response', () async {
    final repository = _QueueRepository();
    final cubit = AccessCubit(AccessUseCases(repository));
    addTearDown(cubit.close);
    await cubit.loadQueue();
    repository.deferred = true;

    final changed = cubit.loadQueue(
      filter: ReviewFilter.all,
      search: 'missing',
    );
    expect(cubit.state.queue, isNull);
    expect(cubit.state.busy, isTrue);
    repository.gates.single.complete();
    await changed;
    expect(cubit.state.queue?.items.single.email, 'missing');
  });

  test(
    'retry retains search, status and page after a network failure',
    () async {
      final repository = _QueueRepository();
      final cubit = AccessCubit(AccessUseCases(repository));
      addTearDown(cubit.close);
      await cubit.loadQueue(filter: ReviewFilter.approved, search: 'applicant');
      await cubit.loadQueue(offset: 50);
      repository.failure = const AppFailure(
        code: 'NETWORK_ERROR',
        message: 'Offline',
      );
      await cubit.loadQueue();
      expect(cubit.state.error?.code, 'NETWORK_ERROR');
      repository.failure = null;

      await cubit.loadQueue();
      expect(repository.queueRequests.last, (
        offset: 50,
        filter: ReviewFilter.approved,
        search: 'applicant',
      ));
      expect(cubit.state.error, isNull);
    },
  );

  test('review criteria participate in state equality and copyWith', () {
    const state = AccessState(
      reviewFilter: ReviewFilter.approved,
      reviewSearch: 'a',
    );
    expect(state.copyWith(busy: true).reviewSearch, 'a');
    expect(state.copyWith(busy: true).reviewFilter, ReviewFilter.approved);
    expect(state, isNot(const AccessState()));
    expect(state.copyWith(reviewSearch: 'b'), isNot(state));
  });

  test(
    'refresh returns to a valid page after its last profile is reviewed',
    () async {
      final repository = _QueueRepository()..total = 51;
      final cubit = AccessCubit(AccessUseCases(repository));
      addTearDown(cubit.close);
      await cubit.loadQueue(filter: ReviewFilter.approved, search: 'applicant');
      await cubit.loadQueue(offset: 50);
      repository.total = 50;

      await cubit.loadQueue();

      expect(cubit.state.queue?.offset, 0);
      expect(cubit.state.queue?.items, isNotEmpty);
      expect(repository.queueRequests.last, (
        offset: 0,
        filter: ReviewFilter.approved,
        search: 'applicant',
      ));
    },
  );

  test('retry repeats a failed request for the next page', () async {
    final repository = _QueueRepository();
    final cubit = AccessCubit(AccessUseCases(repository));
    addTearDown(cubit.close);
    await cubit.loadQueue();
    repository.failure = const AppFailure(
      code: 'NETWORK_ERROR',
      message: 'Offline',
    );
    await cubit.loadQueue(offset: 50);
    expect(cubit.state.queue?.offset, 0);
    repository.failure = null;

    await cubit.loadQueue();

    expect(repository.queueRequests.last.offset, 50);
    expect(cubit.state.queue?.offset, 50);
    expect(cubit.state.error, isNull);
  });
}
