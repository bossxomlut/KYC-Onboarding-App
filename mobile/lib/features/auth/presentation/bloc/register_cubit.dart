import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/domain/result.dart';
import '../../domain/entities/user.dart';
import '../../domain/usecases/register.dart';
import 'auth_form_state.dart';

class RegisterCubit extends Cubit<AuthFormState> {
  RegisterCubit(this._register) : super(const AuthFormState());
  final Register _register;
  Future<void> submit({required String email, required String password}) async {
    if (state.isLoading) return;
    emit(const AuthFormState(status: AuthFormStatus.loading));
    final result = await _register(email: email, password: password);
    if (isClosed) return;
    switch (result) {
      case Success<User>(:final value):
        emit(AuthFormState(
            status: AuthFormStatus.verificationRequired, email: value.email));
      case Failure<User>(:final error):
        // Registration survives delivery failure on the server; resend is
        // available on the verification screen.
        emit(AuthFormState(
            status: error.code == 'EMAIL_DELIVERY_FAILED'
                ? AuthFormStatus.verificationRequired
                : AuthFormStatus.failure,
            email: email.trim().toLowerCase(),
            error: error));
    }
  }
}
