import 'dart:typed_data';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/domain/result.dart';
import '../../domain/entities/kyc_profile.dart';
import '../../domain/usecases/kyc_usecases.dart';

class KycState extends Equatable {
  const KycState({
    this.profile,
    this.busy = false,
    this.error,
    this.uploadProgress,
    this.pendingCaptures = const {},
    this.reviewMedia = const {},
  });
  final KycProfile? profile;
  final bool busy;
  final AppFailure? error;
  final double? uploadProgress;
  final Map<MediaKind, CapturedMedia> pendingCaptures;
  final Map<MediaKind, Uint8List> reviewMedia;
  KycState copyWith({
    KycProfile? profile,
    bool? busy,
    AppFailure? error,
    double? uploadProgress,
    Map<MediaKind, CapturedMedia>? pendingCaptures,
    Map<MediaKind, Uint8List>? reviewMedia,
  }) => KycState(
    profile: profile ?? this.profile,
    busy: busy ?? this.busy,
    error: error,
    uploadProgress: uploadProgress,
    pendingCaptures: pendingCaptures ?? this.pendingCaptures,
    reviewMedia: reviewMedia ?? this.reviewMedia,
  );
  @override
  List<Object?> get props => [
    profile,
    busy,
    error,
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
    required RecoverCapture recoverCapture,
    required DiscardLocalMedia discardLocalMedia,
  }) : _load = loadKyc,
       _save = savePersonalDetails,
       _capture = captureMedia,
       _upload = uploadMedia,
       _privateMedia = loadPrivateMedia,
       _submit = submitKyc,
       _resubmit = resubmitKyc,
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
  final RecoverCapture _recover;
  final DiscardLocalMedia _discard;
  void _update(KycState next) {
    if (!isClosed) emit(next);
  }

  Future<void> load() async {
    if (state.busy) return;
    _update(state.copyWith(busy: true));
    final result = await _load();
    if (isClosed) return;
    switch (result) {
      case Failure<KycProfile>(:final error):
        _update(state.copyWith(busy: false, error: error));
      case Success<KycProfile>(:final value):
        final pending = <MediaKind, CapturedMedia>{...state.pendingCaptures};
        AppFailure? recoveryError;
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
            switch (recovery) {
              case Success<CapturedMedia?>(:final value):
                if (value == null) {
                  pending.remove(kind);
                } else {
                  pending[kind] = value;
                }
              case Failure<CapturedMedia?>(:final error):
                recoveryError = error;
            }
          }
        } else {
          await _discard(value.id);
          pending.clear();
        }
        _update(
          state.copyWith(
            profile: value,
            busy: false,
            pendingCaptures: Map.unmodifiable(pending),
            error: recoveryError,
          ),
        );
    }
  }

  bool _canEdit() {
    if (state.busy) return false;
    if (state.profile?.canEdit ?? false) return true;
    _update(
      state.copyWith(
        error: const AppFailure(
          code: 'PROFILE_LOCKED',
          message:
              'This profile cannot be edited. Refresh its status or start resubmission.',
        ),
      ),
    );
    return false;
  }

  Future<bool> saveDetails(PersonalDetails details) async {
    if (!_canEdit()) return false;
    return _profileOperation(() => _save(details));
  }

  Future<bool> _profileOperation(
    Future<Result<KycProfile>> Function() operation,
  ) async {
    _update(state.copyWith(busy: true));
    final result = await operation();
    switch (result) {
      case Success<KycProfile>(:final value):
        _update(
          state.copyWith(profile: value, busy: false, reviewMedia: const {}),
        );
        return true;
      case Failure<KycProfile>(:final error):
        _update(state.copyWith(busy: false, error: error));
        return false;
    }
  }

  Future<bool> capture(MediaKind kind, {DocumentType? documentType}) async {
    if (!_canEdit()) return false;
    _update(state.copyWith(busy: true));
    final result = await _capture(
      kind,
      state.profile!.id,
      documentType: documentType,
    );
    switch (result) {
      case Failure<CapturedMedia?>(:final error):
        _update(state.copyWith(busy: false, error: error));
        return false;
      case Success<CapturedMedia?>(:final value):
        _update(state.copyWith(busy: false));
        if (value == null) return false;
        _update(
          state.copyWith(
            pendingCaptures: Map.unmodifiable({
              ...state.pendingCaptures,
              kind: value,
            }),
          ),
        );
        return retryUpload(kind);
    }
  }

  Future<bool> retryUpload(MediaKind kind) async {
    if (!_canEdit()) return false;
    final capture = state.pendingCaptures[kind];
    if (capture == null) return false;
    _update(state.copyWith(busy: true, uploadProgress: 0));
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
    switch (result) {
      case Failure<KycProfile>(:final error):
        _update(state.copyWith(busy: false, error: error));
        return false;
      case Success<KycProfile>(:final value):
        final pending = {...state.pendingCaptures}..remove(kind);
        _update(
          state.copyWith(
            profile: value,
            busy: false,
            pendingCaptures: Map.unmodifiable(pending),
            reviewMedia: const {},
          ),
        );
        return true;
    }
  }

  Future<void> loadReviewMedia() async {
    if (state.busy) return;
    _update(state.copyWith(busy: true));
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
        reviewMedia: Map.unmodifiable(images),
        error: failure,
      ),
    );
  }

  Future<bool> submit() async {
    if (state.busy) return false;
    if (!(state.profile?.canSubmit ?? false) ||
        state.pendingCaptures.isNotEmpty) {
      _update(
        state.copyWith(
          error: const AppFailure(
            code: 'INCOMPLETE',
            message: 'Complete and upload every step before submitting.',
          ),
        ),
      );
      return false;
    }
    return _profileOperation(_submit.call);
  }

  Future<bool> resubmit() async {
    if (state.busy || state.profile?.status != KycStatus.rejected) return false;
    return _profileOperation(_resubmit.call);
  }

  Future<void> discardLocalMedia() async {
    final id = state.profile?.id;
    if (id != null) await _discard(id);
    _update(state.copyWith(pendingCaptures: const {}, reviewMedia: const {}));
  }
}
