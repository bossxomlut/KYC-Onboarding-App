import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/domain/result.dart';
import '../../domain/entities/user.dart';
import '../../domain/usecases/resend_verification_code.dart';
import '../../domain/usecases/verify_email.dart';
import 'auth_form_state.dart';

class EmailVerificationCubit extends Cubit<AuthFormState> {
  EmailVerificationCubit(this._verify, this._resend)
    : super(const AuthFormState());
  final VerifyEmail _verify;
  final ResendVerificationCode _resend;
  Timer? _cooldown;

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
    if (state.isLoading || state.isResending || state.resendSeconds > 0) return;
    emit(const AuthFormState(isResending: true));
    final result = await _resend(email);
    if (isClosed) return;
    switch (result) {
      case Success<void>():
        emit(
          const AuthFormState(
            message: 'A new verification code has been sent.',
            resendSeconds: 60,
          ),
        );
        _cooldown?.cancel();
        _cooldown = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (isClosed || state.resendSeconds <= 1) {
            timer.cancel();
            if (!isClosed) {
              emit(
                AuthFormState(
                  status: state.status,
                  user: state.user,
                  error: state.error,
                  message: state.message,
                ),
              );
            }
          } else {
            emit(
              AuthFormState(
                status: state.status,
                user: state.user,
                error: state.error,
                message: state.message,
                resendSeconds: state.resendSeconds - 1,
              ),
            );
          }
        });
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
