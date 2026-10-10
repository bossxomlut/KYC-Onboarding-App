import '../../../../core/domain/result.dart';
import '../repositories/auth_repository.dart';

final class ResetPassword {
  ResetPassword(this._repository);
  final AuthRepository _repository;
  Future<Result<void>> call(
          {required String token, required String newPassword}) =>
      _repository.resetPassword(token: token.trim(), newPassword: newPassword);
}
