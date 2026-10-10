import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/domain/result.dart';
import '../../domain/entities/user.dart';
import '../../domain/usecases/login.dart';
import 'auth_form_state.dart';

class LoginCubit extends Cubit<AuthFormState> {
  LoginCubit(this._login) : super(const AuthFormState());
  final Login _login;
  Future<void> submit({required String email, required String password}) async {
    if (state.isLoading) return;
    emit(AuthFormState(status: AuthFormStatus.loading, email: email.trim()));
    final result = await _login(email: email, password: password);
    if (isClosed) return;
    switch (result) {
      case Success<User>(:final value):
        emit(AuthFormState(status: AuthFormStatus.success, user: value));
      case Failure<User>(:final error):
        emit(AuthFormState(
            status: error.code == 'EMAIL_NOT_VERIFIED'
                ? AuthFormStatus.verificationRequired
                : AuthFormStatus.failure,
            email: email.trim().toLowerCase(),
            error: error));
    }
  }
}
