import '../../../../core/domain/result.dart';
import '../entities/user.dart';

abstract interface class AuthRepository {
  Future<Result<User>> register({
    required String email,
    required String password,
  });
  Future<Result<User>> login({required String email, required String password});
  Future<Result<User>> verifyEmail({
    required String email,
    required String code,
  });
  Future<Result<void>> resendVerificationCode(String email);
  Future<Result<User?>> restoreSession();
  Future<Result<User>> revalidateSession();
  Future<Result<void>> logout();
  Future<Result<void>> requestPasswordReset(String email);
  Future<Result<void>> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  });
}
