import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/domain/result.dart';
import '../../domain/entities/capture_camera.dart';
import '../../domain/entities/kyc_profile.dart';
import '../../domain/usecases/capture_camera_usecases.dart';

enum CaptureCameraStatus { idle, initializing, ready, paused, failure }

class CaptureCameraState extends Equatable {
  const CaptureCameraState({
    this.status = CaptureCameraStatus.idle,
    this.kind,
    this.session,
    this.failure,
  });
  final CaptureCameraStatus status;
  final MediaKind? kind;
  final CaptureCameraSession? session;
  final AppFailure? failure;
  bool get isReady => status == CaptureCameraStatus.ready && session != null;
  @override
  List<Object?> get props => [status, kind, session, failure];
}

/// One camera page owns this Cubit; the hardware lease ends on pause or close.
class CaptureCameraCubit extends Cubit<CaptureCameraState> {
  CaptureCameraCubit({
    required this.initializeCamera,
    required this.setFlash,
    required this.closeCamera,
  }) : super(const CaptureCameraState());

  final InitializeCaptureCamera initializeCamera;
  final SetCaptureCameraFlash setFlash;
  final CloseCaptureCamera closeCamera;
  int _revision = 0;
  bool _active = false;
  bool _needsClose = false;
  bool _disposed = false;
  bool _changingFlash = false;
  Future<void>? _closing;
  Future<void>? _releasing;

  Future<void> initialize(MediaKind kind) async {
    if (_disposed || isClosed) return;
    if (_active &&
        state.kind == kind &&
        (state.isReady || state.status == CaptureCameraStatus.initializing)) {
      return;
    }
    final revision = ++_revision;
    _active = true;
    _needsClose = true;
    emit(
      CaptureCameraState(status: CaptureCameraStatus.initializing, kind: kind),
    );
    final result = await initializeCamera(kind);
    if (_disposed || isClosed || revision != _revision || !_active) return;
    switch (result) {
      case Success<CaptureCameraSession>(:final value):
        emit(
          CaptureCameraState(
            status: CaptureCameraStatus.ready,
            kind: kind,
            session: value,
          ),
        );
      case Failure<CaptureCameraSession>(:final error):
        emit(
          CaptureCameraState(
            status: CaptureCameraStatus.failure,
            kind: kind,
            failure: error,
          ),
        );
    }
  }

  Future<void> pause() async {
    if (isClosed) return;
    if (_active && !_disposed) {
      _active = false;
      ++_revision;
      emit(
        CaptureCameraState(
          status: CaptureCameraStatus.paused,
          kind: state.kind,
        ),
      );
    }
    await _releaseCamera();
  }

  Future<void> resume() async {
    if (_disposed || isClosed || _active || state.kind == null) return;
    await initialize(state.kind!);
  }

  Future<void> toggleFlash() async {
    final session = state.session;
    if (_disposed ||
        isClosed ||
        !state.isReady ||
        session == null ||
        !session.canToggleFlash ||
        _changingFlash) {
      return;
    }
    _changingFlash = true;
    final revision = _revision;
    try {
      final result = await setFlash(!session.flashEnabled);
      if (_disposed || isClosed || revision != _revision || !_active) return;
      switch (result) {
        case Success<CaptureCameraSession>(:final value):
          emit(
            CaptureCameraState(
              status: CaptureCameraStatus.ready,
              kind: state.kind,
              session: value,
            ),
          );
        case Failure<CaptureCameraSession>(:final error):
          emit(
            CaptureCameraState(
              status: CaptureCameraStatus.ready,
              kind: state.kind,
              session: session,
              failure: error,
            ),
          );
      }
    } finally {
      _changingFlash = false;
    }
  }

  Future<void> _releaseCamera() {
    if (!_needsClose) return _releasing ?? Future.value();
    _needsClose = false;
    return _releasing = closeCamera().then<void>((_) {});
  }

  @override
  Future<void> close() {
    if (_closing != null) return _closing!;
    _disposed = true;
    _active = false;
    ++_revision;
    return _closing = _releaseCamera().then((_) => super.close());
  }
}
