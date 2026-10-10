import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/domain/result.dart';
import '../../domain/usecases/request_password_reset.dart';
import '../../domain/usecases/reset_password.dart';
import 'auth_form_state.dart';

class PasswordResetCubit extends Cubit<AuthFormState> {
  PasswordResetCubit(this._request, this._reset) : super(const AuthFormState());
  final RequestPasswordReset _request;
  final ResetPassword _reset;

  Future<void> request(String email) async {
    if (state.isLoading) return;
    emit(const AuthFormState(status: AuthFormStatus.loading));
    final result = await _request(email);
    if (isClosed) return;
    switch (result) {
      case Success<void>():
        emit(
          const AuthFormState(
            status: AuthFormStatus.success,
            message:
                'If an account exists for this email, password reset instructions have been sent.',
          ),
        );
      case Failure<void>(:final error):
        emit(AuthFormState(status: AuthFormStatus.failure, error: error));
    }
  }

  Future<void> reset({
    required String token,
    required String newPassword,
  }) async {
    if (state.isLoading) return;
    emit(const AuthFormState(status: AuthFormStatus.loading));
    final result = await _reset(token: token, newPassword: newPassword);
    if (isClosed) return;
    switch (result) {
      case Success<void>():
        emit(
          const AuthFormState(
            status: AuthFormStatus.success,
            message:
                'Your password has been changed. Sign in with your new password.',
          ),
        );
      case Failure<void>(:final error):
        emit(AuthFormState(status: AuthFormStatus.failure, error: error));
    }
  }
}
