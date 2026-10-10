import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/core/domain/result.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';
import 'package:kyc_onboarding/features/kyc_history/data/models/kyc_history_model.dart';
import 'package:kyc_onboarding/features/kyc_history/domain/entities/kyc_history.dart';
import 'kyc_history_cubit_test.dart'
    show FakeHistoryRepository, historyCubit, networkFailure;
import 'kyc_history_data_test.dart' show submissionJson;

void main() {
  test(
    'foreground history refresh keeps selection and immutable photos',
    () async {
      final repository = FakeHistoryRepository();
      final cubit = historyCubit(repository);
      await cubit.load();
      await cubit.select(cubit.state.submissions.single);
      final photos = cubit.state.media;
      repository.submissionOverride = {
        ...submissionJson,
        'profile': <String, dynamic>{
          ...submissionJson['profile'] as Map<String, dynamic>,
          'status': 'verified',
        },
        'review': null,
      };
      await cubit.refresh();
      expect(cubit.state.selectedSubmission!.id, 'submission-1');
      expect(
        cubit.state.selectedSubmission!.profile.status,
        KycStatus.verified,
      );
      expect(cubit.state.media, same(photos));
      expect(repository.mediaCalls.length, 2);
      await cubit.close();
    },
  );

  test(
    'offline foreground refresh keeps history, selection and photo error',
    () async {
      final repository = FakeHistoryRepository()..failSelfie = true;
      final cubit = historyCubit(repository);
      await cubit.load();
      await cubit.select(cubit.state.submissions.single);
      repository.loadError = networkFailure;
      await cubit.refresh();
      expect(cubit.state.submissions, hasLength(1));
      expect(cubit.state.selectedSubmission!.id, 'submission-1');
      expect(cubit.state.media.keys, [MediaKind.document]);
      expect(cubit.state.mediaError, networkFailure);
      expect(cubit.state.refreshError, networkFailure);
      await cubit.close();
    },
  );

  test(
    'resume queued during pagination refreshes all loaded rounds once',
    () async {
      final repository = FakeHistoryRepository()..total = 2;
      final cubit = historyCubit(repository);
      await cubit.load();
      repository.loadGate = Completer<void>();
      final pagination = cubit.loadMore();
      await cubit.refresh();
      await cubit.refresh();
      repository.loadGate!.complete();
      await pagination;
      expect(repository.offsets, [0, 1, 0, 1]);
      expect(cubit.state.submissions.map((s) => s.id), [
        'submission-1',
        'submission-2',
      ]);
      await cubit.close();
    },
  );

  test(
    'authorization failure on resume clears cached history and photos',
    () async {
      final repository = FakeHistoryRepository();
      final cubit = historyCubit(repository);
      await cubit.load(reviewerUserId: 'applicant');
      await cubit.select(cubit.state.submissions.single);
      repository.loadError = const AppFailure(
        code: 'FORBIDDEN',
        message: 'Access revoked.',
      );
      await cubit.refresh();
      expect(cubit.state.submissions, isEmpty);
      expect(cubit.state.selectedSubmission, isNull);
      expect(cubit.state.media, isEmpty);
      await cubit.close();
    },
  );

  test(
    'refresh deduplicates shifted pages while preserving raw server offsets',
    () async {
      final repository = ShiftedHistoryRepository();
      final cubit = historyCubit(repository);
      addTearDown(cubit.close);
      await cubit.load();
      await cubit.loadMore();
      expect(cubit.state.nextOffset, 40);

      repository.insertBetweenRefreshPages = true;
      await cubit.refresh();
      final refreshedIds = cubit.state.submissions
          .map((entry) => entry.id)
          .toList();
      final refreshedOffset = cubit.state.nextOffset;
      expect(cubit.state.hasMore, isTrue);
      await cubit.loadMore();

      expect(repository.offsets, [0, 20, 0, 20, 40]);
      expect(refreshedOffset, 40);
      expect(cubit.state.nextOffset, 41);
      expect(cubit.state.hasMore, isFalse);
      expect(
        refreshedIds,
        List.generate(39, (index) => 'submission-${40 - index}'),
      );
      expect(
        cubit.state.submissions.map((entry) => entry.id),
        List.generate(40, (index) => 'submission-${40 - index}'),
      );
    },
  );
}

/// A new newest submission shifts the second offset page by one row.
class ShiftedHistoryRepository extends FakeHistoryRepository {
  bool insertBetweenRefreshPages = false;

  @override
  Future<Result<KycHistoryPageResult>> load({
    int offset = 0,
    int limit = 20,
    String? reviewerUserId,
  }) async {
    offsets.add(offset);
    final shiftedPage = insertBetweenRefreshPages && offset > 0;
    final firstVersion = shiftedPage ? 41 - offset : 40 - offset;
    final count = firstVersion < limit ? firstVersion : limit;
    return Success(
      KycHistoryPageResult(
        submissions: List.generate(
          count,
          (index) => KycHistoryModel.submission({
            ...submissionJson,
            'id': 'submission-${firstVersion - index}',
            'version': firstVersion - index,
          }),
        ),
        total: shiftedPage ? 41 : 40,
        offset: offset,
      ),
    );
  }
}
