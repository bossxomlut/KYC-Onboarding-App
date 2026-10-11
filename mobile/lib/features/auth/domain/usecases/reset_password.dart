import '../../../../core/domain/result.dart';
import '../repositories/auth_repository.dart';

final class ResetPassword {
  ResetPassword(this._repository);
  final AuthRepository _repository;
  Future<Result<void>> call({
    required String email,
    required String code,
    required String newPassword,
  }) => _repository.resetPassword(
    email: email.trim().toLowerCase(),
    code: code.trim(),
    newPassword: newPassword,
  );
}
