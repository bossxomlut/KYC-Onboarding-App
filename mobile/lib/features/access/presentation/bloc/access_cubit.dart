import 'dart:async';
import 'dart:typed_data';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/domain/result.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../kyc/domain/entities/kyc_profile.dart';
import '../../domain/entities/access_entities.dart';
import '../../domain/usecases/access_usecases.dart';

class AccessState extends Equatable {
  const AccessState({
    this.user,
    this.request,
    this.users,
    this.requests,
    this.queue,
    this.detail,
    this.media = const {},
    this.busy = false,
    this.needsRevalidation = false,
    this.error,
    this.message,
  });
  final User? user;
  final RoleRequest? request;
  final PageResult<ManagedUser>? users;
  final PageResult<RoleRequest>? requests;
  final PageResult<ReviewSummary>? queue;
  final ReviewDetail? detail;
  final Map<MediaKind, Uint8List> media;
  final bool busy;
  final bool needsRevalidation;
  final AppFailure? error;
  final String? message;
  AccessState copyWith({
    User? user,
    RoleRequest? request,
    PageResult<ManagedUser>? users,
    PageResult<RoleRequest>? requests,
    PageResult<ReviewSummary>? queue,
    ReviewDetail? detail,
    Map<MediaKind, Uint8List>? media,
    bool? busy,
    bool? needsRevalidation,
    AppFailure? error,
    String? message,
  }) => AccessState(
    user: user ?? this.user,
    request: request ?? this.request,
    users: users ?? this.users,
    requests: requests ?? this.requests,
    queue: queue ?? this.queue,
    detail: detail ?? this.detail,
    media: media ?? this.media,
    busy: busy ?? this.busy,
    needsRevalidation: needsRevalidation ?? this.needsRevalidation,
    error: error,
    message: message,
  );
  @override
  List<Object?> get props => [
    user,
    request,
    users,
    requests,
    queue,
    detail,
    media,
    busy,
    needsRevalidation,
    error,
    message,
  ];
}

/// Page scoped; every administrative route creates and owns one instance.
class AccessCubit extends Cubit<AccessState> {
  AccessCubit(this._actions) : super(const AccessState());
  final AccessUseCases _actions;
  int _resumeGeneration = 0;
  Future<void> Function(int)? _pendingRead;
  final List<Completer<void>> _pendingWaiters = [];

  void prepareForResume() {
    if (isClosed) return;
    _resumeGeneration++;
    _update(state.copyWith(needsRevalidation: true, error: state.error));
  }

  bool _currentRead(int generation) =>
      !isClosed && generation == _resumeGeneration;

  Future<void> _read(Future<void> Function(int) operation) async {
    if (isClosed) return;
    if (state.busy) {
      _pendingRead = operation;
      final waiter = Completer<void>();
      _pendingWaiters.add(waiter);
      return waiter.future;
    }
    _update(state.copyWith(busy: true));
    try {
      await operation(_resumeGeneration);
    } finally {
      if (!isClosed && state.busy) {
        _update(state.copyWith(busy: false, error: state.error));
      }
      await _drainPendingRead();
    }
  }

  Future<void> _drainPendingRead() async {
    final pending = _pendingRead;
    if (pending == null || state.busy) return;
    final waiters = List<Completer<void>>.of(_pendingWaiters);
    _pendingRead = null;
    _pendingWaiters.clear();
    try {
      if (!isClosed) await _read(pending);
    } finally {
      for (final waiter in waiters) {
        if (!waiter.isCompleted) waiter.complete();
      }
    }
  }

  Future<void> _refreshAfterMutation(Future<void> Function() fallback) async {
    if (_pendingRead != null) {
      await _drainPendingRead();
    } else if (!state.needsRevalidation) {
      await fallback();
    }
  }

  @override
  Future<void> close() {
    _pendingRead = null;
    for (final waiter in _pendingWaiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _pendingWaiters.clear();
    return super.close();
  }

  void _update(AccessState value) {
    if (!isClosed) emit(value);
  }

  void _failure(AppFailure error) {
    if ([
      'FORBIDDEN',
      'SELF_REVIEW',
      'SELF_REVIEW_FORBIDDEN',
      'REVIEWER_REQUIRED',
      'KYC_REVIEW_NOT_PENDING',
      'KYC_REVIEW_NOT_FOUND',
      'KYC_REVIEW_CHANGED',
      'SESSION_EXPIRED',
      'UNAUTHORIZED',
    ].contains(error.code)) {
      _update(
        AccessState(
          user: state.user,
          error: error,
          needsRevalidation: state.needsRevalidation,
        ),
      );
    } else {
      _update(state.copyWith(busy: false, error: error));
    }
  }

  Future<void> loadAccess() => _read((generation) async {
    final user = await _actions.currentUser();
    if (!_currentRead(generation)) return;
    if (user case Failure<User>(:final error)) {
      _failure(error);
      return;
    }
    // Publish server-derived permissions independently of request status IO.
    _update(state.copyWith(user: (user as Success<User>).value, busy: true));
    final request = await _actions.ownRequest();
    if (!_currentRead(generation)) return;
    switch (request) {
      case Success<RoleRequest?>(:final value):
        _update(AccessState(user: user.value, request: value));
      case Failure<RoleRequest?>(:final error):
        _failure(error);
    }
  });

  Future<bool> _mutate<T>(
    Future<Result<T>> Function() operation, {
    String? message,
  }) async {
    if (isClosed || state.busy || state.needsRevalidation) return false;
    _update(state.copyWith(busy: true));
    final result = await operation();
    if (isClosed) return false;
    switch (result) {
      case Success<T>():
        _update(state.copyWith(busy: false, message: message));
        return true;
      case Failure<T>(:final error):
        _failure(error);
        unawaited(_drainPendingRead());
        return false;
    }
  }

  Future<bool> requestReviewer(String reason) async {
    if (isClosed || state.busy || state.needsRevalidation) return false;
    _update(state.copyWith(busy: true));
    final result = await _actions.requestReviewer(reason);
    if (isClosed) return false;
    switch (result) {
      case Success<RoleRequest>(:final value):
        _update(
          state.copyWith(
            request: value,
            busy: false,
            message: 'Your request was sent to the super admin.',
          ),
        );
        unawaited(_drainPendingRead());
        return true;
      case Failure<RoleRequest>(:final error):
        _failure(error);
        unawaited(_drainPendingRead());
        return false;
    }
  }

  Future<void> loadAdmin({int offset = 0, int requestOffset = 0}) =>
      _read((generation) async {
        final users = await _actions.users(offset: offset);
        if (!_currentRead(generation)) return;
        if (users case Failure<PageResult<ManagedUser>>(:final error)) {
          _failure(error);
          return;
        }
        final requests = await _actions.requests(offset: requestOffset);
        if (!_currentRead(generation)) return;
        switch (requests) {
          case Success<PageResult<RoleRequest>>(:final value):
            _update(
              state.copyWith(
                users: (users as Success<PageResult<ManagedUser>>).value,
                requests: value,
                busy: false,
                needsRevalidation: false,
              ),
            );
          case Failure<PageResult<RoleRequest>>(:final error):
            _failure(error);
        }
      });

  Future<bool> createUser(String email, String password, UserRole role) async {
    if (!await _mutate(
      () => _actions.createUser(email: email, password: password, role: role),
    )) {
      return false;
    }
    await _refreshAfterMutation(
      () => loadAdmin(
        offset: state.users?.offset ?? 0,
        requestOffset: state.requests?.offset ?? 0,
      ),
    );
    _update(
      state.copyWith(
        error: state.error,
        message:
            'Account created. The user must verify the OTP sent to their email before signing in.',
      ),
    );
    return true;
  }

  Future<bool> changeRole(String userId, UserRole role) async {
    if (!await _mutate(() => _actions.changeRole(userId, role))) return false;
    await _refreshAfterMutation(
      () => loadAdmin(
        offset: state.users?.offset ?? 0,
        requestOffset: state.requests?.offset ?? 0,
      ),
    );
    _update(
      state.copyWith(error: state.error, message: 'Permissions updated.'),
    );
    return true;
  }

  Future<bool> decideRequest(
    String requestId,
    RoleRequestStatus decision, {
    String? reason,
  }) async {
    if (!await _mutate(
      () => _actions.decideRequest(requestId, decision, reason: reason),
    )) {
      return false;
    }
    await _refreshAfterMutation(
      () => loadAdmin(
        offset: state.users?.offset ?? 0,
        requestOffset: state.requests?.offset ?? 0,
      ),
    );
    _update(
      state.copyWith(error: state.error, message: 'Request ${decision.name}.'),
    );
    return true;
  }

  Future<void> loadQueue({int offset = 0}) => _read((generation) async {
    final result = await _actions.reviewQueue(offset: offset);
    if (!_currentRead(generation)) return;
    switch (result) {
      case Success<PageResult<ReviewSummary>>(:final value):
        _update(
          state.copyWith(queue: value, busy: false, needsRevalidation: false),
        );
      case Failure<PageResult<ReviewSummary>>(:final error):
        _failure(error);
    }
  });

  Future<void> loadDetail(String userId) => _read((generation) async {
    final result = await _actions.reviewDetail(userId);
    if (!_currentRead(generation)) return;
    if (result case Failure<ReviewDetail>(:final error)) {
      _failure(error);
      return;
    }
    final detail = (result as Success<ReviewDetail>).value;
    _update(
      AccessState(
        detail: detail,
        busy: true,
        needsRevalidation: state.needsRevalidation,
      ),
    );
    final media = <MediaKind, Uint8List>{};
    AppFailure? mediaError;
    for (final kind in MediaKind.values) {
      if ((kind == MediaKind.document
              ? detail.profile.document
              : detail.profile.selfie) ==
          null) {
        continue;
      }
      final image = await _actions.media(
        userId,
        kind,
        submissionId: detail.submissionId,
      );
      if (!_currentRead(generation)) return;
      switch (image) {
        case Success<List<int>>(:final value):
          media[kind] = Uint8List.fromList(value);
        case Failure<List<int>>(:final error):
          if (const {
            'FORBIDDEN',
            'SELF_REVIEW',
            'SELF_REVIEW_FORBIDDEN',
            'REVIEWER_REQUIRED',
            'KYC_REVIEW_NOT_PENDING',
            'KYC_REVIEW_NOT_FOUND',
            'KYC_REVIEW_CHANGED',
            'SESSION_EXPIRED',
            'UNAUTHORIZED',
          }.contains(error.code)) {
            _failure(error);
            return;
          }
          mediaError = error;
      }
    }
    _update(
      state.copyWith(
        busy: false,
        media: Map.unmodifiable(media),
        error: mediaError,
        needsRevalidation: mediaError == null ? false : state.needsRevalidation,
      ),
    );
  });

  Future<bool> decideProfile(
    String userId,
    ReviewDecision decision, {
    required String submissionId,
    String? actorId,
    String? reason,
    List<KycStep> requiredSteps = const [],
  }) async {
    if (isClosed || state.busy || state.needsRevalidation) return false;
    if (state.detail?.userId != userId ||
        state.detail?.submissionId != submissionId) {
      _failure(
        const AppFailure(
          code: 'KYC_REVIEW_CHANGED',
          message:
              'This submission has changed. Reload it before making a decision.',
        ),
      );
      return false;
    }
    if (!await _mutate(
      () => _actions.decideProfile(
        userId,
        decision,
        submissionId: submissionId,
        actorId: actorId,
        reason: reason,
        requiredSteps: requiredSteps,
      ),
    )) {
      return false;
    }
    // A completed decision leaves no private images in this page's state.
    _update(
      AccessState(
        message: 'Review decision saved.',
        needsRevalidation: state.needsRevalidation,
      ),
    );
    unawaited(_drainPendingRead());
    return true;
  }
}
