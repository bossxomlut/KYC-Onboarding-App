import '../../../../core/domain/result.dart';
import '../entities/user.dart';
import '../repositories/auth_repository.dart';

final class RestoreSession {
  RestoreSession(this._repository);
  final AuthRepository _repository;
  Future<Result<User?>> call() => _repository.restoreSession();
}
