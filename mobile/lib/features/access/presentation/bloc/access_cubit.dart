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
    error,
    message,
  ];
}

/// Page scoped; every administrative route creates and owns one instance.
class AccessCubit extends Cubit<AccessState> {
  AccessCubit(this._actions) : super(const AccessState());
  final AccessUseCases _actions;
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
      'SESSION_EXPIRED',
      'UNAUTHORIZED',
    ].contains(error.code)) {
      _update(AccessState(user: state.user, error: error));
    } else {
      _update(state.copyWith(busy: false, error: error));
    }
  }

  Future<void> loadAccess() async {
    if (state.busy) return;
    _update(state.copyWith(busy: true));
    final user = await _actions.currentUser();
    if (isClosed) return;
    if (user case Failure<User>(:final error)) {
      _failure(error);
      return;
    }
    final request = await _actions.ownRequest();
    if (isClosed) return;
    switch (request) {
      case Success<RoleRequest?>(:final value):
        _update(
          AccessState(user: (user as Success<User>).value, request: value),
        );
      case Failure<RoleRequest?>(:final error):
        _failure(error);
    }
  }

  Future<bool> _mutate<T>(
    Future<Result<T>> Function() operation, {
    String? message,
  }) async {
    if (state.busy) return false;
    _update(state.copyWith(busy: true));
    final result = await operation();
    if (isClosed) return false;
    switch (result) {
      case Success<T>():
        _update(state.copyWith(busy: false, message: message));
        return true;
      case Failure<T>(:final error):
        _failure(error);
        return false;
    }
  }

  Future<bool> requestReviewer(String reason) async {
    if (state.busy) return false;
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
        return true;
      case Failure<RoleRequest>(:final error):
        _failure(error);
        return false;
    }
  }

  Future<void> loadAdmin({int offset = 0, int requestOffset = 0}) async {
    if (state.busy) return;
    _update(state.copyWith(busy: true));
    final users = await _actions.users(offset: offset);
    if (isClosed) return;
    if (users case Failure<PageResult<ManagedUser>>(:final error)) {
      _failure(error);
      return;
    }
    final requests = await _actions.requests(offset: requestOffset);
    if (isClosed) return;
    switch (requests) {
      case Success<PageResult<RoleRequest>>(:final value):
        _update(
          state.copyWith(
            users: (users as Success<PageResult<ManagedUser>>).value,
            requests: value,
            busy: false,
          ),
        );
      case Failure<PageResult<RoleRequest>>(:final error):
        _failure(error);
    }
  }

  Future<bool> createUser(String email, String password, UserRole role) async {
    if (!await _mutate(
      () => _actions.createUser(email: email, password: password, role: role),
    )) {
      return false;
    }
    await loadAdmin();
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
    await loadAdmin(
      offset: state.users?.offset ?? 0,
      requestOffset: state.requests?.offset ?? 0,
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
    await loadAdmin(
      offset: state.users?.offset ?? 0,
      requestOffset: state.requests?.offset ?? 0,
    );
    _update(
      state.copyWith(error: state.error, message: 'Request ${decision.name}.'),
    );
    return true;
  }

  Future<void> loadQueue({int offset = 0}) async {
    if (state.busy) return;
    _update(state.copyWith(busy: true));
    final result = await _actions.reviewQueue(offset: offset);
    if (isClosed) return;
    switch (result) {
      case Success<PageResult<ReviewSummary>>(:final value):
        _update(state.copyWith(queue: value, busy: false));
      case Failure<PageResult<ReviewSummary>>(:final error):
        _failure(error);
    }
  }

  Future<void> loadDetail(String userId) async {
    if (state.busy) return;
    _update(AccessState(busy: true));
    final result = await _actions.reviewDetail(userId);
    if (isClosed) return;
    if (result case Failure<ReviewDetail>(:final error)) {
      _failure(error);
      return;
    }
    final detail = (result as Success<ReviewDetail>).value;
    _update(AccessState(detail: detail, busy: true));
    final media = <MediaKind, Uint8List>{};
    AppFailure? mediaError;
    for (final kind in MediaKind.values) {
      if ((kind == MediaKind.document
              ? detail.profile.document
              : detail.profile.selfie) ==
          null) {
        continue;
      }
      final image = await _actions.media(userId, kind);
      if (isClosed) return;
      switch (image) {
        case Success<List<int>>(:final value):
          media[kind] = Uint8List.fromList(value);
        case Failure<List<int>>(:final error):
          if ([
            'FORBIDDEN',
            'SELF_REVIEW',
            'SELF_REVIEW_FORBIDDEN',
            'REVIEWER_REQUIRED',
            'KYC_REVIEW_NOT_PENDING',
            'KYC_REVIEW_NOT_FOUND',
            'SESSION_EXPIRED',
            'UNAUTHORIZED',
          ].contains(error.code)) {
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
      ),
    );
  }

  Future<bool> decideProfile(
    String userId,
    ReviewDecision decision, {
    String? actorId,
    String? reason,
    List<KycStep> requiredSteps = const [],
  }) async {
    if (!await _mutate(
      () => _actions.decideProfile(
        userId,
        decision,
        actorId: actorId,
        reason: reason,
        requiredSteps: requiredSteps,
      ),
    )) {
      return false;
    }
    // A completed decision leaves no private images in this page's state.
    _update(const AccessState(message: 'Review decision saved.'));
    return true;
  }
}
