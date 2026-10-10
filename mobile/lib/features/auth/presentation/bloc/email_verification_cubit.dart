import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/domain/result.dart';
import '../../domain/entities/user.dart';
import '../../domain/usecases/resend_verification_code.dart';
import '../../domain/usecases/verify_email.dart';
import 'auth_form_state.dart';

class EmailVerificationCubit extends Cubit<AuthFormState> {
  EmailVerificationCubit(this._verify, this._resend, {DateTime Function()? now})
    : _now = now ?? DateTime.now,
      super(const AuthFormState());
  final VerifyEmail _verify;
  final ResendVerificationCode _resend;
  Timer? _cooldown;
  final DateTime Function() _now;
  DateTime? _resendAvailableAt;

  void startCooldown({Duration duration = const Duration(seconds: 30)}) {
    if (isClosed) return;
    _resendAvailableAt = _now().add(duration);
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
        user: state.user,
        email: state.email,
        error: state.error,
        message: state.message,
        resendSeconds: seconds,
        isResending: state.isResending,
      ),
    );
  }

  Future<void> submit({required String email, required String code}) async {
    if (state.isLoading || state.isResending) return;
    emit(
      AuthFormState(
        status: AuthFormStatus.loading,
        resendSeconds: state.resendSeconds,
      ),
    );
    final result = await _verify(email: email, code: code);
    if (isClosed) return;
    switch (result) {
      case Success<User>(:final value):
        _cooldown?.cancel();
        _resendAvailableAt = null;
        emit(AuthFormState(status: AuthFormStatus.success, user: value));
      case Failure<User>(:final error):
        emit(
          AuthFormState(
            status: AuthFormStatus.failure,
            error: error,
            resendSeconds: state.resendSeconds,
          ),
        );
    }
  }

  Future<void> resend(String email) async {
    reconcileCooldown();
    if (state.isLoading || state.isResending || state.resendSeconds > 0) return;
    emit(const AuthFormState(isResending: true));
    final result = await _resend(email);
    if (isClosed) return;
    switch (result) {
      case Success<void>():
        emit(
          const AuthFormState(
            message: 'A new verification code has been sent.',
            resendSeconds: 30,
          ),
        );
        startCooldown();
      case Failure<void>(:final error):
        emit(AuthFormState(status: AuthFormStatus.failure, error: error));
    }
  }

  @override
  Future<void> close() {
    _cooldown?.cancel();
    return super.close();
  }
}
