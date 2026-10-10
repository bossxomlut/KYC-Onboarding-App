import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/domain/result.dart';
import '../../domain/entities/user.dart';
import '../../domain/usecases/logout.dart';
import '../../domain/usecases/restore_session.dart';

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
  const AuthAuthenticated(this.user, {this.isSigningOut = false, this.error});
  final User user;
  final bool isSigningOut;
  final AppFailure? error;
  @override
  List<Object?> get props => [user, isSigningOut, error];
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
  AuthSessionCubit(this._restore, this._logout)
    : super(const AuthInitializing());
  final RestoreSession _restore;
  final Logout _logout;
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

  void signedIn(User user) {
    if (isClosed) return;
    _sessionEpoch++;
    emit(AuthAuthenticated(user));
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
        emit(AuthAuthenticated(previous.user, error: error));
        return false;
    }
  }
}
