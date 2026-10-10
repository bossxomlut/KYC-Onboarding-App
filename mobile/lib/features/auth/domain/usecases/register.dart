import '../../../../core/domain/result.dart';
import '../entities/user.dart';
import '../repositories/auth_repository.dart';

final class Register {
  Register(this._repository);
  final AuthRepository _repository;
  Future<Result<User>> call({
    required String email,
    required String password,
  }) => _repository.register(
    email: email.trim().toLowerCase(),
    password: password,
  );
}
