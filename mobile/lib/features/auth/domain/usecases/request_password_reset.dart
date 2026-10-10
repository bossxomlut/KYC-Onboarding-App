import '../../../../core/domain/result.dart';
import '../repositories/auth_repository.dart';

final class RequestPasswordReset {
  RequestPasswordReset(this._repository);
  final AuthRepository _repository;
  Future<Result<void>> call(String email) =>
      _repository.requestPasswordReset(email.trim().toLowerCase());
}
