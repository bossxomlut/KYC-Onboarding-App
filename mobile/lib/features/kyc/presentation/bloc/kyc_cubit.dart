import 'dart:async';
import 'dart:typed_data';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/domain/result.dart';
import '../../domain/entities/kyc_profile.dart';
import '../../domain/entities/document_capture_crop.dart';
import '../../domain/usecases/kyc_usecases.dart';

enum KycOperation {
  none,
  loadingProfile,
  capturing,
  uploading,
  savingDetails,
  loadingMedia,
  submitting,
  resubmitting,
  verifying,
}

enum KycErrorSource { profile, media, operation, captureRecovery }

class KycState extends Equatable {
  const KycState({
    this.profile,
    this.busy = false,
    this.refreshing = false,
    this.operation = KycOperation.none,
    this.error,
    this.errorSource,
    this.uploadProgress,
    this.pendingCaptures = const {},
    this.reviewMedia = const {},
  });
  final KycProfile? profile;
  final bool busy;
  final bool refreshing;
  final KycOperation operation;
  final AppFailure? error;
  final KycErrorSource? errorSource;
  final double? uploadProgress;
  final Map<MediaKind, CapturedMedia> pendingCaptures;
  final Map<MediaKind, Uint8List> reviewMedia;
  KycState copyWith({
    KycProfile? profile,
    bool? busy,
    bool? refreshing,
    KycOperation? operation,
    AppFailure? error,
    KycErrorSource? errorSource,
    double? uploadProgress,
    Map<MediaKind, CapturedMedia>? pendingCaptures,
    Map<MediaKind, Uint8List>? reviewMedia,
  }) => KycState(
    profile: profile ?? this.profile,
    busy: busy ?? this.busy,
    refreshing: refreshing ?? this.refreshing,
    operation: operation ?? this.operation,
    error: error,
    errorSource: error == null ? null : errorSource ?? this.errorSource,
    uploadProgress: uploadProgress,
    pendingCaptures: pendingCaptures ?? this.pendingCaptures,
    reviewMedia: reviewMedia ?? this.reviewMedia,
  );
  @override
  List<Object?> get props => [
    profile,
    busy,
    refreshing,
    operation,
    error,
    errorSource,
    uploadProgress,
    pendingCaptures,
    reviewMedia,
  ];
}

/// Flow-scoped; a provider in the authenticated routing shell owns its lifecycle.
class KycCubit extends Cubit<KycState> {
  KycCubit({
    required LoadKyc loadKyc,
    required SavePersonalDetails savePersonalDetails,
    required CaptureMedia captureMedia,
    required UploadMedia uploadMedia,
    required LoadPrivateMedia loadPrivateMedia,
    required SubmitKyc submitKyc,
    required ResubmitKyc resubmitKyc,
    required VerifyIdentity verifyIdentity,
    required RecoverCapture recoverCapture,
    required DiscardLocalMedia discardLocalMedia,
  }) : _load = loadKyc,
       _save = savePersonalDetails,
       _capture = captureMedia,
       _upload = uploadMedia,
       _privateMedia = loadPrivateMedia,
       _submit = submitKyc,
       _resubmit = resubmitKyc,
       _verify = verifyIdentity,
       _recover = recoverCapture,
       _discard = discardLocalMedia,
       super(const KycState());
  final LoadKyc _load;
  final SavePersonalDetails _save;
  final CaptureMedia _capture;
  final UploadMedia _upload;
  final LoadPrivateMedia _privateMedia;
  final SubmitKyc _submit;
  final ResubmitKyc _resubmit;
  final VerifyIdentity _verify;
  final RecoverCapture _recover;
  final DiscardLocalMedia _discard;
  Future<void>? _profileRead;
  Completer<void>? _queuedRefresh;
  int _profileGeneration = 0;
  int _activeProfileGeneration = 0;
  bool _resumeNeedsFreshRead = false;
  int _reviewMediaViews = 0;
  void _update(KycState next) {
    if (!isClosed) emit(next);
  }

  Future<void> load() => _requestProfile(silent: false);

  /// Reconciles server progress without interrupting the current form or photo.
  /// Requests during a write/camera/media operation share one trailing GET.
  Future<void> refresh() {
    if (_resumeNeedsFreshRead) {
      _resumeNeedsFreshRead = false;
      // A trailing read may have started while the app was backgrounded.
      if (_profileRead != null) _profileGeneration++;
    }
    return _requestProfile(silent: state.profile != null);
  }

  /// Called on real background entry; resume must not reuse an older snapshot.
  /// This invalidates reads without starting IO while the app is backgrounded.
  void prepareForResume() {
    if (isClosed) return;
    _profileGeneration++;
    _resumeNeedsFreshRead = true;
  }

  void retainReviewMediaView() {
    if (!isClosed) _reviewMediaViews++;
  }

  void releaseReviewMediaView() {
    if (_reviewMediaViews > 0) _reviewMediaViews--;
  }

  Future<void> _requestProfile({required bool silent}) {
    if (isClosed) return Future.value();
    if (_profileRead != null &&
        _activeProfileGeneration == _profileGeneration) {
      return _profileRead!;
    }
    if (_profileRead != null) {
      _queuedRefresh ??= Completer<void>();
      return _queuedRefresh!.future;
    }
    if (state.busy) {
      _queuedRefresh ??= Completer<void>();
      return _queuedRefresh!.future;
    }
    return _runProfileRead(silent: silent);
  }

  Future<void> _runProfileRead({required bool silent}) {
    final generation = _profileGeneration;
    _activeProfileGeneration = generation;
    final request = _loadProfile(silent: silent, generation: generation)
        .whenComplete(() {
          if (!isClosed && generation != _profileGeneration) {
            _update(
              state.copyWith(
                busy: false,
                refreshing: false,
                operation: KycOperation.none,
                error: state.error,
                errorSource: state.errorSource,
              ),
            );
          }
          _profileRead = null;
          _drainRefresh();
        });
    _profileRead = request;
    return request;
  }

  void _drainRefresh() {
    final pending = _queuedRefresh;
    if (pending == null || state.busy || _profileRead != null) return;
    _queuedRefresh = null;
    if (isClosed) {
      pending.complete();
      return;
    }
    unawaited(
      _runProfileRead(silent: state.profile != null).then(
        (_) => pending.complete(),
        onError: (Object error, StackTrace trace) =>
            pending.completeError(error, trace),
      ),
    );
  }

  bool _isCurrentProfileRead(int generation) =>
      !isClosed && generation == _profileGeneration;

  Future<void> _waitForProfileReads() async {
    // Completing an old read can start the fresh resume read before we wake.
    while (!isClosed && _profileRead != null) {
      await _profileRead;
    }
  }

  Future<void> _loadProfile({
    required bool silent,
    required int generation,
  }) async {
    final previousError = silent ? state.error : null;
    final previousSource = silent ? state.errorSource : null;
    _update(
      state.copyWith(
        busy: !silent,
        refreshing: silent,
        operation: silent ? KycOperation.none : KycOperation.loadingProfile,
        error: previousError,
        errorSource: previousSource,
      ),
    );
    final result = await _load();
    if (!_isCurrentProfileRead(generation)) return;
    switch (result) {
      case Failure<KycProfile>(:final error):
        _update(
          state.copyWith(
            busy: false,
            refreshing: false,
            operation: KycOperation.none,
            error: previousSource == KycErrorSource.operation
                ? previousError
                : error,
            errorSource: previousSource == KycErrorSource.operation
                ? previousSource
                : KycErrorSource.profile,
          ),
        );
      case Success<KycProfile>(:final value):
        final changedKinds = MediaKind.values
            .where(
              (kind) => _mediaId(state.profile, kind) != _mediaId(value, kind),
            )
            .toSet();
        final reloadKinds = MediaKind.values
            .where(
              (kind) =>
                  _mediaId(value, kind) != null &&
                  ((changedKinds.contains(kind) &&
                          (_reviewMediaViews > 0 ||
                              state.reviewMedia.containsKey(kind))) ||
                      (_reviewMediaViews > 0 &&
                          !state.reviewMedia.containsKey(kind))),
            )
            .toSet();
        final images = {...state.reviewMedia}
          ..removeWhere((kind, _) => changedKinds.contains(kind));
        final pending = <MediaKind, CapturedMedia>{...state.pendingCaptures};
        AppFailure? recoveryError;
        var acknowledgedCapture = false;
        if (value.canEdit) {
          for (final kind in MediaKind.values) {
            final existingMedia = kind == MediaKind.document
                ? value.document
                : value.selfie;
            final recovery = await _recover(
              kind,
              value.id,
              confirmedCaptureId: existingMedia?.captureId,
            );
            if (!_isCurrentProfileRead(generation)) return;
            switch (recovery) {
              case Success<CapturedMedia?>(:final value):
                if (value == null) {
                  final draftId = pending[kind]?.captureId;
                  if (draftId != null && draftId == existingMedia?.captureId) {
                    images[kind] = pending[kind]!.bytes;
                    pending.remove(kind);
                    acknowledgedCapture = true;
                  }
                } else {
                  pending[kind] = value;
                }
              case Failure<CapturedMedia?>(:final error):
                recoveryError = error;
            }
          }
        } else {
          await _discard(value.id);
          if (!_isCurrentProfileRead(generation)) return;
          pending.clear();
        }
        _update(
          state.copyWith(
            profile: value,
            pendingCaptures: Map.unmodifiable(pending),
            reviewMedia: Map.unmodifiable(images),
            error:
                recoveryError ??
                ((previousSource == KycErrorSource.operation &&
                            value.canEdit &&
                            !acknowledgedCapture) ||
                        previousSource == KycErrorSource.media
                    ? previousError
                    : null),
            errorSource: recoveryError == null
                ? previousSource
                : KycErrorSource.captureRecovery,
          ),
        );
        AppFailure? mediaError;
        for (final kind in reloadKinds) {
          if (_mediaId(value, kind) == null) continue;
          final result = await _privateMedia(kind);
          if (!_isCurrentProfileRead(generation)) return;
          switch (result) {
            case Success<Uint8List>(:final value):
              images[kind] = value;
            case Failure<Uint8List>(:final error):
              mediaError = error;
          }
        }
        final retainedError =
            state.errorSource == KycErrorSource.media &&
                reloadKinds.isNotEmpty &&
                mediaError == null
            ? null
            : state.error;
        _update(
          state.copyWith(
            busy: false,
            refreshing: false,
            operation: KycOperation.none,
            reviewMedia: Map.unmodifiable(images),
            error: mediaError ?? retainedError,
            errorSource: mediaError == null
                ? state.errorSource
                : KycErrorSource.media,
          ),
        );
    }
  }

  String? _mediaId(KycProfile? profile, MediaKind kind) =>
      (kind == MediaKind.document ? profile?.document : profile?.selfie)?.id;

  bool _canEdit() {
    if (isClosed || state.busy) return false;
    if (state.profile?.canEdit ?? false) return true;
    _update(
      state.copyWith(
        error: const AppFailure(
          code: 'PROFILE_LOCKED',
          message:
              'This profile cannot be edited. Refresh its status or start resubmission.',
        ),
        errorSource: KycErrorSource.operation,
      ),
    );
    return false;
  }

  Future<bool> saveDetails(PersonalDetails details) async {
    if (_profileRead != null) await _waitForProfileReads();
    if (!_canEdit()) return false;
    return _profileOperation(() => _save(details), KycOperation.savingDetails);
  }

  Future<bool> _profileOperation(
    Future<Result<KycProfile>> Function() operation,
    KycOperation operationKind,
  ) async {
    _update(state.copyWith(busy: true, operation: operationKind));
    final result = await operation();
    if (isClosed) return false;
    switch (result) {
      case Success<KycProfile>(:final value):
        _update(
          state.copyWith(
            profile: value,
            busy: false,
            operation: KycOperation.none,
            reviewMedia: Map.unmodifiable({
              for (final entry in state.reviewMedia.entries)
                if (_mediaId(state.profile, entry.key) ==
                    _mediaId(value, entry.key))
                  entry.key: entry.value,
            }),
          ),
        );
        _drainRefresh();
        return true;
      case Failure<KycProfile>(:final error):
        _update(
          state.copyWith(
            busy: false,
            operation: KycOperation.none,
            error: error,
            errorSource: KycErrorSource.operation,
          ),
        );
        _drainRefresh();
        return false;
    }
  }

  Future<bool> capture(
    MediaKind kind, {
    DocumentType? documentType,
    DocumentCaptureCrop? crop,
    bool uploadImmediately = true,
  }) async {
    if (_profileRead != null) await _waitForProfileReads();
    if (!_canEdit()) return false;
    _update(state.copyWith(busy: true, operation: KycOperation.capturing));
    final result = await _capture(
      kind,
      state.profile!.id,
      documentType: documentType,
      crop: crop,
    );
    if (isClosed) return false;
    switch (result) {
      case Failure<CapturedMedia?>(:final error):
        _update(
          state.copyWith(
            busy: false,
            operation: KycOperation.none,
            error: error,
            errorSource: KycErrorSource.operation,
          ),
        );
        _drainRefresh();
        return false;
      case Success<CapturedMedia?>(:final value):
        _update(state.copyWith(busy: false, operation: KycOperation.none));
        if (value == null) {
          _drainRefresh();
          return false;
        }
        _update(
          state.copyWith(
            pendingCaptures: Map.unmodifiable({
              ...state.pendingCaptures,
              kind: value,
            }),
          ),
        );
        if (!uploadImmediately) {
          _drainRefresh();
          return true;
        }
        return retryUpload(kind);
    }
  }

  Future<bool> retryUpload(MediaKind kind) async {
    if (_profileRead != null) await _waitForProfileReads();
    if (!_canEdit()) return false;
    final capture = state.pendingCaptures[kind];
    if (capture == null) return false;
    _update(
      state.copyWith(
        busy: true,
        operation: KycOperation.uploading,
        uploadProgress: 0,
      ),
    );
    final result = await _upload(
      capture,
      onProgress: (sent, total) {
        if (total > 0) {
          _update(
            state.copyWith(
              busy: true,
              uploadProgress: (sent / total).clamp(0, 1),
            ),
          );
        }
      },
    );
    if (isClosed) return false;
    switch (result) {
      case Failure<KycProfile>(:final error):
        _update(
          state.copyWith(
            busy: false,
            operation: KycOperation.none,
            error: error,
            errorSource: KycErrorSource.operation,
          ),
        );
        _drainRefresh();
        return false;
      case Success<KycProfile>(:final value):
        final pending = {...state.pendingCaptures}..remove(kind);
        _update(
          state.copyWith(
            profile: value,
            busy: false,
            operation: KycOperation.none,
            pendingCaptures: Map.unmodifiable(pending),
            reviewMedia: Map.unmodifiable({
              ...state.reviewMedia,
              kind: capture.bytes,
            }),
          ),
        );
        _drainRefresh();
        return true;
    }
  }

  Future<void> loadReviewMedia() async {
    if (_profileRead != null) await _waitForProfileReads();
    if (isClosed || state.busy) return;
    final profileError = state.errorSource == KycErrorSource.profile
        ? state.error
        : null;
    _update(
      state.copyWith(
        busy: true,
        operation: KycOperation.loadingMedia,
        error: profileError,
        errorSource: KycErrorSource.profile,
      ),
    );
    final images = <MediaKind, Uint8List>{};
    AppFailure? failure;
    for (final kind in MediaKind.values) {
      if ((kind == MediaKind.document
              ? state.profile?.document
              : state.profile?.selfie) ==
          null) {
        continue;
      }
      final result = await _privateMedia(kind);
      if (isClosed) return;
      switch (result) {
        case Success<Uint8List>(:final value):
          images[kind] = value;
        case Failure<Uint8List>(:final error):
          failure = error;
      }
    }
    _update(
      state.copyWith(
        busy: false,
        operation: KycOperation.none,
        reviewMedia: Map.unmodifiable(images),
        error: failure ?? profileError,
        errorSource: failure == null
            ? KycErrorSource.profile
            : KycErrorSource.media,
      ),
    );
    _drainRefresh();
  }

  /// Retries failed reads only; submission and upload still require user intent.
  Future<void> retryRead() =>
      state.errorSource == KycErrorSource.profile ||
          state.errorSource == KycErrorSource.captureRecovery
      ? load()
      : loadReviewMedia();

  Future<bool> submit() async {
    if (_profileRead != null) await _waitForProfileReads();
    if (isClosed || state.busy) return false;
    if (!(state.profile?.canSubmit ?? false) ||
        state.pendingCaptures.isNotEmpty) {
      _update(
        state.copyWith(
          error: const AppFailure(
            code: 'INCOMPLETE',
            message: 'Complete and upload every step before submitting.',
          ),
          errorSource: KycErrorSource.operation,
        ),
      );
      return false;
    }
    return _profileOperation(_submit.call, KycOperation.submitting);
  }

  Future<bool> resubmit() async {
    if (_profileRead != null) await _waitForProfileReads();
    if (isClosed || state.busy || state.profile?.status != KycStatus.rejected) {
      return false;
    }
    return _profileOperation(_resubmit.call, KycOperation.resubmitting);
  }

  /// Runs only on explicit user intent, and preserves manual submission/review.
  Future<bool> verifyIdentity() async {
    if (_profileRead != null) await _waitForProfileReads();
    if (!_canEdit()) return false;
    final profile = state.profile!;
    if (profile.document == null ||
        profile.selfie == null ||
        state.pendingCaptures.isNotEmpty) {
      _update(
        state.copyWith(
          error: const AppFailure(
            code: 'INCOMPLETE',
            message: 'Upload both photos before running identity checks.',
          ),
          errorSource: KycErrorSource.operation,
        ),
      );
      return false;
    }
    final checks = profile.verification;
    if (checks?.status == VerificationStatus.completed &&
        checks?.documentId == profile.document?.id &&
        checks?.selfieId == profile.selfie?.id) {
      return true;
    }
    if (checks == null || checks.status == VerificationStatus.disabled) {
      _update(
        state.copyWith(
          error: const AppFailure(
            code: 'KYC_VERIFICATION_UNAVAILABLE',
            message:
                'Automated identity checks are unavailable. You can submit for manual review.',
          ),
          errorSource: KycErrorSource.operation,
        ),
      );
      return false;
    }
    return _profileOperation(_verify.call, KycOperation.verifying);
  }

  Future<void> discardLocalMedia() async {
    final id = state.profile?.id;
    if (id != null) await _discard(id);
    _update(state.copyWith(pendingCaptures: const {}, reviewMedia: const {}));
  }

  @override
  Future<void> close() {
    _queuedRefresh?.complete();
    _queuedRefresh = null;
    return super.close();
  }
}
