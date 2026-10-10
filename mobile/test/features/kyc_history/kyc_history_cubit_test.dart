import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/core/domain/result.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';
import 'package:kyc_onboarding/features/kyc_history/data/models/kyc_history_model.dart';
import 'package:kyc_onboarding/features/kyc_history/domain/entities/kyc_history.dart';
import 'package:kyc_onboarding/features/kyc_history/domain/repositories/kyc_history_repository.dart';
import 'package:kyc_onboarding/features/kyc_history/domain/usecases/kyc_history_usecases.dart';
import 'package:kyc_onboarding/features/kyc_history/presentation/bloc/kyc_history_cubit.dart';
import 'kyc_history_data_test.dart' show submissionJson;

void main() {
  test('late photos cannot reappear after the detail sheet closes', () async {
    final repository = FakeHistoryRepository();
    final cubit = historyCubit(repository);
    await cubit.load();
    repository.mediaGate = Completer<void>();
    final pending = cubit.select(cubit.state.submissions.single);
    cubit.clearSelection();
    repository.mediaGate!.complete();
    await pending;
    expect(cubit.state.selectedSubmission, isNull);
    expect(cubit.state.media, isEmpty);
    expect(cubit.state.mediaLoading, isFalse);
    await cubit.close();
  });
  test('late photo responses do not emit after route disposal', () async {
    final repository = FakeHistoryRepository();
    final cubit = historyCubit(repository);
    await cubit.load();
    repository.mediaGate = Completer<void>();
    final pending = cubit.select(cubit.state.submissions.single);
    await cubit.close();
    repository.mediaGate!.complete();
    await pending;
    expect(cubit.isClosed, isTrue);
  });
  test(
    'retrying history media preserves the successful original image',
    () async {
      final repository = FakeHistoryRepository()..failSelfie = true;
      final cubit = historyCubit(repository);
      await cubit.load(reviewerUserId: 'applicant');
      await cubit.select(cubit.state.submissions.single);
      expect(cubit.state.media.keys, [MediaKind.document]);
      expect(cubit.state.mediaError!.code, 'NETWORK_ERROR');
      repository.failSelfie = false;
      await cubit.retryMedia();
      expect(cubit.state.media.length, 2);
      expect(cubit.state.mediaError, isNull);
      expect(repository.mediaCalls, [
        'submission-1/document',
        'submission-1/selfie',
        'submission-1/selfie',
      ]);
      expect(
        repository.reviewerUserIds.every((id) => id == 'applicant'),
        isTrue,
      );
      cubit.clearSelection();
      expect(cubit.state.selectedSubmission, isNull);
      expect(cubit.state.media, isEmpty);
      await cubit.close();
    },
  );

  test(
    'pagination preserves earlier rounds on failure and retries the same offset',
    () async {
      final repository = FakeHistoryRepository()..total = 2;
      final cubit = historyCubit(repository);
      await cubit.load();
      repository.loadError = networkFailure;
      await cubit.loadMore();
      expect(cubit.state.submissions.single.version, 1);
      expect(cubit.state.error, networkFailure);
      repository.loadError = null;
      await cubit.loadMore();
      expect(cubit.state.submissions.map((entry) => entry.id), [
        'submission-1',
        'submission-2',
      ]);
      expect(repository.offsets, [0, 1, 1]);
      expect(cubit.state.hasMore, isFalse);
      await cubit.close();
    },
  );

  test('late history responses do not emit after route disposal', () async {
    final repository = FakeHistoryRepository()..loadGate = Completer<void>();
    final cubit = historyCubit(repository);
    final pending = cubit.load();
    await cubit.close();
    repository.loadGate!.complete();
    await pending;
    expect(cubit.isClosed, isTrue);
  });

  test(
    'revoked media authorization clears private history and photos',
    () async {
      final repository = FakeHistoryRepository();
      final cubit = historyCubit(repository);
      await cubit.load();
      repository.mediaError = const AppFailure(
        code: 'FORBIDDEN',
        message: 'Reviewer access was revoked.',
      );
      await cubit.select(cubit.state.submissions.single);
      expect(cubit.state.submissions, isEmpty);
      expect(cubit.state.selectedSubmission, isNull);
      expect(cubit.state.media, isEmpty);
      expect(cubit.state.error!.code, 'FORBIDDEN');
      await cubit.close();
    },
  );
}

const networkFailure = AppFailure(
  code: 'NETWORK_ERROR',
  message: 'Connection interrupted. Try again.',
);

KycHistoryCubit historyCubit(FakeHistoryRepository repository) =>
    KycHistoryCubit(
      loadHistory: LoadKycHistory(repository),
      loadMedia: LoadKycHistoryMedia(repository),
    );

class FakeHistoryRepository implements KycHistoryRepository {
  Map<String, dynamic>? submissionOverride;
  bool failSelfie = false;
  int total = 1;
  AppFailure? loadError;
  AppFailure? mediaError;
  Completer<void>? loadGate;
  Completer<void>? mediaGate;
  final offsets = <int>[];
  final mediaCalls = <String>[];
  final reviewerUserIds = <String?>[];
  final image = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aSu8AAAAASUVORK5CYII=',
  );
  @override
  Future<Result<KycHistoryPageResult>> load({
    int offset = 0,
    int limit = 20,
    String? reviewerUserId,
  }) async {
    offsets.add(offset);
    reviewerUserIds.add(reviewerUserId);
    if (loadGate != null) await loadGate!.future;
    if (loadError != null) return Failure(loadError!);
    return Success(
      KycHistoryPageResult(
        submissions: total == 0
            ? []
            : [
                KycHistoryModel.submission({
                  ...(submissionOverride ?? submissionJson),
                  'id': 'submission-${offset + 1}',
                  'version': offset + 1,
                }),
              ],
        total: total,
        offset: offset,
      ),
    );
  }

  @override
  Future<Result<Uint8List>> media(
    String submissionId,
    MediaKind kind, {
    String? reviewerUserId,
  }) async {
    mediaCalls.add('$submissionId/${kind.name}');
    reviewerUserIds.add(reviewerUserId);
    if (mediaGate != null) await mediaGate!.future;
    if (mediaError != null) return Failure(mediaError!);
    if (kind == MediaKind.selfie && failSelfie) {
      return const Failure(networkFailure);
    }
    return Success(image);
  }
}
