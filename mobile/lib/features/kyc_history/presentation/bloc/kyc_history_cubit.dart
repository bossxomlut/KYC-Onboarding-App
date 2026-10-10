import 'dart:typed_data';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/domain/result.dart';
import '../../../kyc/domain/entities/kyc_profile.dart';
import '../../domain/entities/kyc_history.dart';
import '../../domain/usecases/kyc_history_usecases.dart';

class KycHistoryState extends Equatable {
  const KycHistoryState({
    this.submissions = const [],
    this.total = 0,
    this.nextOffset = 0,
    this.loading = false,
    this.loadingMore = false,
    this.refreshing = false,
    this.refreshError,
    this.error,
    this.selectedSubmission,
    this.media = const {},
    this.mediaLoading = false,
    this.mediaError,
  });
  final List<KycHistorySubmission> submissions;
  final int total;
  final int nextOffset;
  final bool loading;
  final bool loadingMore;
  final bool refreshing;
  final AppFailure? refreshError;
  final AppFailure? error;
  final KycHistorySubmission? selectedSubmission;
  final Map<MediaKind, Uint8List> media;
  final bool mediaLoading;
  final AppFailure? mediaError;
  bool get hasMore => nextOffset < total;
  KycHistoryState copyWith({
    List<KycHistorySubmission>? submissions,
    int? total,
    int? nextOffset,
    bool? loading,
    bool? loadingMore,
    bool? refreshing,
    AppFailure? refreshError,
    bool clearRefreshError = false,
    AppFailure? error,
    KycHistorySubmission? selectedSubmission,
    bool clearSelection = false,
    Map<MediaKind, Uint8List>? media,
    bool? mediaLoading,
    AppFailure? mediaError,
  }) => KycHistoryState(
    submissions: submissions ?? this.submissions,
    total: total ?? this.total,
    nextOffset: nextOffset ?? this.nextOffset,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    refreshing: refreshing ?? this.refreshing,
    refreshError: clearRefreshError ? null : refreshError ?? this.refreshError,
    error: error,
    selectedSubmission: clearSelection
        ? null
        : selectedSubmission ?? this.selectedSubmission,
    media: media ?? this.media,
    mediaLoading: mediaLoading ?? this.mediaLoading,
    mediaError: mediaError,
  );
  @override
  List<Object?> get props => [
    submissions,
    total,
    nextOffset,
    loading,
    loadingMore,
    refreshing,
    refreshError,
    error,
    selectedSubmission,
    media,
    mediaLoading,
    mediaError,
  ];
}

/// Page-scoped history; immutable snapshots never touch the active KYC flow.
class KycHistoryCubit extends Cubit<KycHistoryState> {
  KycHistoryCubit({
    required LoadKycHistory loadHistory,
    required LoadKycHistoryMedia loadMedia,
  }) : _load = loadHistory,
       _media = loadMedia,
       super(const KycHistoryState());
  final LoadKycHistory _load;
  final LoadKycHistoryMedia _media;
  String? _reviewerUserId;
  int _listGeneration = 0;
  int _mediaGeneration = 0;
  bool _refreshQueued = false;

  void _update(KycHistoryState value) {
    if (!isClosed) emit(value);
  }

  bool _isAuthorizationFailure(AppFailure error) => const {
    'FORBIDDEN',
    'UNAUTHORIZED',
    'SESSION_EXPIRED',
    'REVIEWER_REQUIRED',
    'SELF_REVIEW',
    'SELF_REVIEW_FORBIDDEN',
  }.contains(error.code);
  bool _clearOnAuthorizationFailure(AppFailure error) {
    if (!_isAuthorizationFailure(error)) return false;
    _listGeneration++;
    _mediaGeneration++;
    _refreshQueued = false;
    _update(KycHistoryState(error: error));
    return true;
  }

  Future<void> load({String? reviewerUserId}) async {
    if (isClosed || state.loading || state.refreshing) return;
    if (reviewerUserId != null) _reviewerUserId = reviewerUserId;
    final generation = ++_listGeneration;
    _mediaGeneration++;
    _update(const KycHistoryState(loading: true));
    final result = await _load(reviewerUserId: _reviewerUserId);
    if (isClosed || generation != _listGeneration) return;
    switch (result) {
      case Failure<KycHistoryPageResult>(:final error):
        _update(KycHistoryState(error: error));
      case Success<KycHistoryPageResult>(:final value):
        _update(
          KycHistoryState(
            submissions: List.unmodifiable(value.submissions),
            total: value.total,
            nextOffset: value.offset + value.submissions.length,
          ),
        );
    }
    await _drainRefresh();
  }

  /// Reconcile loaded rounds without replacing an open immutable snapshot.
  Future<void> refresh() async {
    if (isClosed) return;
    if (state.loading || state.loadingMore || state.refreshing) {
      _refreshQueued = true;
      return;
    }
    final generation = ++_listGeneration;
    final target = state.nextOffset > 20 ? state.nextOffset : 20;
    _update(
      state.copyWith(
        refreshing: true,
        clearRefreshError: true,
        error: state.error,
        mediaError: state.mediaError,
      ),
    );
    final submissions = <KycHistorySubmission>[];
    final knownIds = <String>{};
    var offset = 0;
    var total = 0;
    do {
      final result = await _load(
        offset: offset,
        reviewerUserId: _reviewerUserId,
      );
      if (isClosed || generation != _listGeneration) return;
      switch (result) {
        case Failure<KycHistoryPageResult>(:final error):
          if (!_clearOnAuthorizationFailure(error)) {
            _update(
              state.copyWith(
                refreshing: false,
                refreshError: error,
                error: state.error,
                mediaError: state.mediaError,
              ),
            );
          }
          await _drainRefresh();
          return;
        case Success<KycHistoryPageResult>(:final value):
          submissions.addAll(
            value.submissions.where((entry) => knownIds.add(entry.id)),
          );
          total = value.total;
          offset = value.submissions.isEmpty
              ? total
              : value.offset + value.submissions.length;
      }
    } while (offset < total && offset < target);
    final selected = state.selectedSubmission;
    KycHistorySubmission? reconciled;
    if (selected != null) {
      for (final submission in submissions) {
        if (submission.id == selected.id) {
          reconciled = submission;
          break;
        }
      }
    }
    _update(
      state.copyWith(
        submissions: List.unmodifiable(submissions),
        selectedSubmission: reconciled,
        total: total,
        nextOffset: offset,
        refreshing: false,
        clearRefreshError: true,
        mediaError: state.mediaError,
      ),
    );
    await _drainRefresh();
  }

  Future<void> _drainRefresh() async {
    if (_refreshQueued && !isClosed) {
      _refreshQueued = false;
      await refresh();
    }
  }

  Future<void> loadMore() async {
    if (isClosed ||
        state.loading ||
        state.loadingMore ||
        state.refreshing ||
        !state.hasMore) {
      return;
    }
    final generation = _listGeneration;
    _update(state.copyWith(loadingMore: true));
    final result = await _load(
      offset: state.nextOffset,
      reviewerUserId: _reviewerUserId,
    );
    if (isClosed || generation != _listGeneration) return;
    switch (result) {
      case Failure<KycHistoryPageResult>(:final error):
        if (!_clearOnAuthorizationFailure(error)) {
          _update(state.copyWith(loadingMore: false, error: error));
        }
      case Success<KycHistoryPageResult>(:final value):
        final knownIds = state.submissions.map((entry) => entry.id).toSet();
        _update(
          state.copyWith(
            submissions: List.unmodifiable([
              ...state.submissions,
              ...value.submissions.where((entry) => knownIds.add(entry.id)),
            ]),
            total: value.total,
            nextOffset: value.submissions.isEmpty
                ? value.total
                : value.offset + value.submissions.length,
            loadingMore: false,
          ),
        );
    }
    await _drainRefresh();
  }

  Future<void> select(KycHistorySubmission submission) async {
    if (isClosed) return;
    _mediaGeneration++;
    _update(
      state.copyWith(
        selectedSubmission: submission,
        media: const {},
        mediaLoading: false,
      ),
    );
    await retryMedia();
  }

  Future<void> retryMedia() async {
    final submission = state.selectedSubmission;
    if (isClosed || submission == null || state.mediaLoading) return;
    final generation = _mediaGeneration;
    _update(state.copyWith(mediaLoading: true));
    final images = <MediaKind, Uint8List>{...state.media};
    AppFailure? failure;
    for (final kind in MediaKind.values) {
      final metadata = kind == MediaKind.document
          ? submission.profile.document
          : submission.profile.selfie;
      if (metadata == null || images.containsKey(kind)) continue;
      final result = await _media(
        submission.id,
        kind,
        reviewerUserId: _reviewerUserId,
      );
      if (isClosed || generation != _mediaGeneration) return;
      switch (result) {
        case Success<Uint8List>(:final value):
          images[kind] = value;
        case Failure<Uint8List>(:final error):
          if (_clearOnAuthorizationFailure(error)) return;
          failure = error;
      }
    }
    _update(
      state.copyWith(
        media: Map.unmodifiable(images),
        mediaLoading: false,
        mediaError: failure,
      ),
    );
  }

  void clearSelection() {
    _mediaGeneration++;
    _update(
      state.copyWith(
        clearSelection: true,
        media: const {},
        mediaLoading: false,
        error: state.error,
      ),
    );
  }
}
