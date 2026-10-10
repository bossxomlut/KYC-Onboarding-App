import '../../../../core/domain/result.dart';
import '../repositories/auth_repository.dart';

final class ResendVerificationCode {
  ResendVerificationCode(this._repository);
  final AuthRepository _repository;
  Future<Result<void>> call(String email) =>
      _repository.resendVerificationCode(email.trim().toLowerCase());
}
