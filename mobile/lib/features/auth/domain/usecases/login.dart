import '../../../../core/domain/result.dart';
import '../entities/user.dart';
import '../repositories/auth_repository.dart';

final class Login {
  Login(this._repository);
  final AuthRepository _repository;
  Future<Result<User>> call(
          {required String email, required String password}) =>
      _repository.login(email: email.trim().toLowerCase(), password: password);
}
