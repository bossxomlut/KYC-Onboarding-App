import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/domain/result.dart';
import '../../domain/usecases/request_password_reset.dart';
import '../../domain/usecases/reset_password.dart';
import 'auth_form_state.dart';

class PasswordResetCubit extends Cubit<AuthFormState> {
  PasswordResetCubit(this._request, this._reset, {DateTime Function()? now})
    : _now = now ?? DateTime.now,
      super(const AuthFormState());
  final RequestPasswordReset _request;
  final ResetPassword _reset;
  final DateTime Function() _now;
  Timer? _cooldown;
  DateTime? _resendAvailableAt;
  int _generation = 0;

  DateTime? get resendAvailableAt => _resendAvailableAt;

  void resetForm({String? email}) {
    if (isClosed) return;
    _generation++;
    _cooldown?.cancel();
    _resendAvailableAt = null;
    emit(AuthFormState(email: email));
  }

  void startCooldown({DateTime? availableAt}) {
    if (isClosed) return;
    _resendAvailableAt = availableAt ?? _now().add(const Duration(seconds: 30));
    _cooldown?.cancel();
    reconcileCooldown();
    if (state.resendSeconds > 0) {
      _cooldown = Timer.periodic(
        const Duration(seconds: 1),
        (_) => reconcileCooldown(),
      );
    }
  }

  void reconcileCooldown() {
    if (isClosed) return;
    final deadline = _resendAvailableAt;
    if (deadline == null) return;
    final remaining = deadline.difference(_now()).inMicroseconds;
    final seconds = remaining <= 0
        ? 0
        : (remaining / Duration.microsecondsPerSecond).ceil();
    if (seconds == 0) {
      _cooldown?.cancel();
      _resendAvailableAt = null;
    }
    if (seconds == state.resendSeconds) return;
    emit(
      AuthFormState(
        status: state.status,
        email: state.email,
        error: state.error,
        message: state.message,
        resendSeconds: seconds,
        isResending: state.isResending,
      ),
    );
  }

  Future<bool> request(String email) async {
    if (isClosed || state.isLoading || state.isResending) return false;
    final generation = _generation;
    final normalizedEmail = email.trim().toLowerCase();
    emit(AuthFormState(status: AuthFormStatus.loading, email: normalizedEmail));
    final result = await _request(normalizedEmail);
    if (isClosed || generation != _generation) return false;
    switch (result) {
      case Success<void>():
        emit(
          AuthFormState(
            status: AuthFormStatus.success,
            email: normalizedEmail,
            message:
                'If an account exists for this email, a password reset code has been sent.',
          ),
        );
        startCooldown();
        return true;
      case Failure<void>(:final error):
        emit(
          AuthFormState(
            status: AuthFormStatus.failure,
            email: normalizedEmail,
            error: error,
          ),
        );
        return false;
    }
  }

  Future<void> resend(String email) async {
    if (isClosed) return;
    reconcileCooldown();
    if (state.isLoading || state.isResending || state.resendSeconds > 0) return;
    final generation = _generation;
    final normalizedEmail = email.trim().toLowerCase();
    emit(AuthFormState(email: normalizedEmail, isResending: true));
    final result = await _request(normalizedEmail);
    if (isClosed || generation != _generation) return;
    switch (result) {
      case Success<void>():
        emit(
          AuthFormState(
            email: normalizedEmail,
            message:
                'If an account exists for this email, a new password reset code has been sent.',
          ),
        );
        startCooldown();
      case Failure<void>(:final error):
        emit(
          AuthFormState(
            status: AuthFormStatus.failure,
            email: normalizedEmail,
            error: error,
          ),
        );
    }
  }

  Future<bool> reset({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    if (isClosed || state.isLoading || state.isResending) return false;
    final generation = _generation;
    final normalizedEmail = email.trim().toLowerCase();
    emit(
      AuthFormState(
        status: AuthFormStatus.loading,
        email: normalizedEmail,
        resendSeconds: state.resendSeconds,
      ),
    );
    final result = await _reset(
      email: normalizedEmail,
      code: code,
      newPassword: newPassword,
    );
    if (isClosed || generation != _generation) return result is Success<void>;
    switch (result) {
      case Success<void>():
        _cooldown?.cancel();
        _resendAvailableAt = null;
        emit(
          AuthFormState(
            status: AuthFormStatus.success,
            email: normalizedEmail,
            message:
                'Your password has been changed. Sign in with your new password.',
          ),
        );
        return true;
      case Failure<void>(:final error):
        emit(
          AuthFormState(
            status: AuthFormStatus.failure,
            email: normalizedEmail,
            error: error,
            resendSeconds: state.resendSeconds,
          ),
        );
        return false;
    }
  }

  @override
  Future<void> close() {
    _cooldown?.cancel();
    return super.close();
  }
}
