import 'package:equatable/equatable.dart';

import '../../../../core/domain/result.dart';
import '../../domain/entities/user.dart';

enum AuthFormStatus { initial, loading, success, failure, verificationRequired }

final class AuthFormState extends Equatable {
  const AuthFormState({
    this.status = AuthFormStatus.initial,
    this.user,
    this.email,
    this.error,
    this.message,
    this.resendSeconds = 0,
    this.isResending = false,
  });
  final AuthFormStatus status;
  final User? user;
  final String? email;
  final AppFailure? error;
  final String? message;
  final int resendSeconds;
  final bool isResending;
  bool get isLoading => status == AuthFormStatus.loading;
  @override
  List<Object?> get props => [
    status,
    user,
    email,
    error,
    message,
    resendSeconds,
    isResending,
  ];
}
