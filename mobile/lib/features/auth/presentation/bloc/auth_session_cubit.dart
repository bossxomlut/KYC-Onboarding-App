import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/domain/result.dart';
import '../../domain/entities/user.dart';
import '../../domain/usecases/logout.dart';
import '../../domain/usecases/restore_session.dart';
import '../../domain/usecases/revalidate_session.dart';

sealed class AuthSessionState extends Equatable {
  const AuthSessionState();
  @override
  List<Object?> get props => [];
}

final class AuthInitializing extends AuthSessionState {
  const AuthInitializing();
}

final class AuthSignedOut extends AuthSessionState {
  const AuthSignedOut();
}

final class AuthEmailVerificationRequired extends AuthSessionState {
  const AuthEmailVerificationRequired(this.email);
  final String email;
  @override
  List<Object?> get props => [email];
}

final class AuthAuthenticated extends AuthSessionState {
  const AuthAuthenticated(
    this.user, {
    this.isSigningOut = false,
    this.error,
    this.isRevalidating = false,
    this.revalidationError,
  });
  final User user;
  final bool isSigningOut;
  final AppFailure? error;
  final bool isRevalidating;
  final AppFailure? revalidationError;
  @override
  List<Object?> get props => [
    user,
    isSigningOut,
    error,
    isRevalidating,
    revalidationError,
  ];
}

final class AuthConnectionFailure extends AuthSessionState {
  const AuthConnectionFailure(this.error);
  final AppFailure error;
  @override
  List<Object?> get props => [error];
}

/// App scoped. Only the app composition root coordinates this session with
/// routing and the authenticated KYC flow.
class AuthSessionCubit extends Cubit<AuthSessionState> {
  AuthSessionCubit(this._restore, this._logout, {this._revalidateSession})
    : super(const AuthInitializing());
  final RestoreSession _restore;
  final Logout _logout;
  final RevalidateSession? _revalidateSession;
  Future<bool>? _revalidation;
  int? _revalidationEpoch;
  int? _revalidationGeneration;
  Future<bool>? _trailingRevalidation;
  int? _trailingEpoch;
  int _freshnessGeneration = 0;
  int? _requestedGeneration;
  bool _restoring = false;
  int _sessionEpoch = 0;
  String? get sessionScope {
    final current = state;
    return current is AuthAuthenticated
        ? '${current.user.id}:$_sessionEpoch'
        : null;
  }

  Future<void> restore() async {
    if (_restoring) return;
    _restoring = true;
    final startingEpoch = _sessionEpoch;
    emit(const AuthInitializing());
    final result = await _restore();
    _restoring = false;
    if (isClosed || startingEpoch != _sessionEpoch) return;
    switch (result) {
      case Success<User?>(:final value):
        _sessionEpoch++;
        emit(value == null ? const AuthSignedOut() : AuthAuthenticated(value));
      case Failure<User?>(:final error):
        emit(AuthConnectionFailure(error));
    }
  }

  /// Checks live permissions without removing any authenticated route state.
  Future<bool> revalidate() {
    final current = state;
    if (isClosed || current is! AuthAuthenticated || current.isSigningOut) {
      return Future.value(false);
    }
    final check = _revalidateSession;
    if (check == null) return Future.value(false);
    final epoch = _sessionEpoch;
    _requestedGeneration = _freshnessGeneration;
    final existing = _revalidation;
    if (existing != null && _revalidationEpoch == epoch) {
      if (_revalidationGeneration == _freshnessGeneration) return existing;
      final trailing = _trailingRevalidation;
      if (trailing != null && _trailingEpoch == epoch) return trailing;
      _trailingEpoch = epoch;
      late final Future<bool> queued;
      queued = _checkAfterPending(check, existing, epoch).whenComplete(() {
        if (identical(_trailingRevalidation, queued)) {
          _trailingRevalidation = null;
          _trailingEpoch = null;
        }
      });
      _trailingRevalidation = queued;
      return queued;
    }
    return _startRevalidation(check, current, epoch, _freshnessGeneration);
  }

  /// A new background cycle needs fresher account data, not a new session.
  void markForRevalidation() {
    if (!isClosed && state is AuthAuthenticated) _freshnessGeneration++;
  }

  Future<bool> _startRevalidation(
    RevalidateSession check,
    AuthAuthenticated current,
    int epoch,
    int generation,
  ) {
    _revalidationEpoch = epoch;
    _revalidationGeneration = generation;
    final operation = _checkSession(check, current, epoch, generation);
    late final Future<bool> tracked;
    tracked = operation.whenComplete(() {
      if (identical(_revalidation, tracked)) {
        _revalidation = null;
        _revalidationEpoch = null;
        _revalidationGeneration = null;
      }
    });
    _revalidation = tracked;
    return tracked;
  }

  Future<bool> _checkAfterPending(
    RevalidateSession check,
    Future<bool> pending,
    int epoch,
  ) async {
    await pending;
    while (true) {
      final current = state;
      if (isClosed ||
          epoch != _sessionEpoch ||
          current is! AuthAuthenticated ||
          current.isSigningOut ||
          _requestedGeneration != _freshnessGeneration) {
        return false;
      }
      final generation = _freshnessGeneration;
      final active = _revalidation;
      if (active != null &&
          _revalidationEpoch == epoch &&
          _revalidationGeneration != generation) {
        await active;
        continue;
      }
      final operation = active != null && _revalidationEpoch == epoch
          ? active
          : _startRevalidation(check, current, epoch, generation);
      final confirmed = await operation;
      if (_freshnessGeneration == generation) return confirmed;
    }
  }

  Future<bool> _checkSession(
    RevalidateSession check,
    AuthAuthenticated previous,
    int epoch,
    int generation,
  ) async {
    emit(
      AuthAuthenticated(
        previous.user,
        error: previous.error,
        isRevalidating: true,
      ),
    );
    final result = await check();
    final current = state;
    if (isClosed ||
        epoch != _sessionEpoch ||
        current is! AuthAuthenticated ||
        current.user.id != previous.user.id) {
      return false;
    }
    if (generation != _freshnessGeneration) {
      if (_requestedGeneration != _freshnessGeneration) {
        emit(
          AuthAuthenticated(
            current.user,
            isSigningOut: current.isSigningOut,
            error: current.error,
            revalidationError: current.revalidationError,
          ),
        );
      }
      return false;
    }
    switch (result) {
      case Success<User>(:final value):
        if (value.id != previous.user.id) {
          await sessionInvalidated();
          return false;
        }
        emit(
          AuthAuthenticated(
            value,
            isSigningOut: current.isSigningOut,
            error: current.error,
          ),
        );
        return !current.isSigningOut;
      case Failure<User>(:final error):
        if (error.code == 'SESSION_EXPIRED') {
          await sessionInvalidated();
        } else {
          emit(
            AuthAuthenticated(
              current.user,
              isSigningOut: current.isSigningOut,
              error: current.error,
              revalidationError: error,
            ),
          );
        }
        return false;
    }
  }

  void signedIn(User user) {
    if (isClosed) return;
    _sessionEpoch++;
    emit(AuthAuthenticated(user));
  }

  /// Updates live account permissions without replacing the current session.
  void updateUser(User user) {
    final current = state;
    if (!isClosed &&
        current is AuthAuthenticated &&
        current.user.id == user.id) {
      _freshnessGeneration++;
      emit(
        AuthAuthenticated(
          user,
          isSigningOut: current.isSigningOut,
          error: current.error,
          isRevalidating: current.isRevalidating,
          revalidationError: current.revalidationError,
        ),
      );
    }
  }

  void verificationRequired(String email) =>
      emit(AuthEmailVerificationRequired(email));
  void cancelVerification() {
    if (isClosed) return;
    _sessionEpoch++;
    emit(const AuthSignedOut());
  }

  Future<void> sessionInvalidated() async {
    if (!isClosed) {
      _sessionEpoch++;
      emit(const AuthSignedOut());
    }
  }

  Future<bool> signOut() async {
    final previous = state;
    if (previous is! AuthAuthenticated || previous.isSigningOut) return false;
    final startingEpoch = _sessionEpoch;
    emit(AuthAuthenticated(previous.user, isSigningOut: true));
    final result = await _logout();
    if (isClosed || startingEpoch != _sessionEpoch) return false;
    switch (result) {
      case Success<void>():
        _sessionEpoch++;
        emit(const AuthSignedOut());
        return true;
      case Failure<void>(:final error):
        final current = state;
        final user =
            current is AuthAuthenticated && current.user.id == previous.user.id
            ? current.user
            : previous.user;
        emit(AuthAuthenticated(user, error: error));
        return false;
    }
  }
}
