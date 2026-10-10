import '../../../../core/domain/result.dart';
import '../entities/user.dart';
import '../repositories/auth_repository.dart';

final class VerifyEmail {
  VerifyEmail(this._repository);
  final AuthRepository _repository;
  Future<Result<User>> call({required String email, required String code}) =>
      _repository.verifyEmail(
          email: email.trim().toLowerCase(), code: code.trim());
}
