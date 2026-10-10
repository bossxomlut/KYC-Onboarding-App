import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/domain/result.dart';
import '../../domain/usecases/request_password_reset.dart';
import '../../domain/usecases/reset_password.dart';
import 'auth_form_state.dart';

class PasswordResetCubit extends Cubit<AuthFormState> {
  PasswordResetCubit(this._request, this._reset) : super(const AuthFormState());
  final RequestPasswordReset _request;
  final ResetPassword _reset;
  int _generation = 0;

  void resetForm() {
    if (isClosed) return;
    _generation++;
    emit(const AuthFormState());
  }

  Future<void> request(String email) async {
    if (state.isLoading) return;
    final generation = _generation;
    emit(const AuthFormState(status: AuthFormStatus.loading));
    final result = await _request(email);
    if (isClosed || generation != _generation) return;
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

  Future<bool> reset({
    required String token,
    required String newPassword,
  }) async {
    if (isClosed || state.isLoading) return false;
    final generation = _generation;
    emit(const AuthFormState(status: AuthFormStatus.loading));
    final result = await _reset(token: token, newPassword: newPassword);
    if (isClosed || generation != _generation) return result is Success<void>;
    switch (result) {
      case Success<void>():
        emit(
          const AuthFormState(
            status: AuthFormStatus.success,
            message:
                'Your password has been changed. Sign in with your new password.',
          ),
        );
        return true;
      case Failure<void>(:final error):
        emit(AuthFormState(status: AuthFormStatus.failure, error: error));
        return false;
    }
  }
}
