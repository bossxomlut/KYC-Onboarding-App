import '../../domain/entities/user.dart';

final class UserModel {
  UserModel.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      email = json['email'] as String,
      emailVerified = json['emailVerified'] as bool,
      role = UserRole.fromApi(json['role']);
  final String id;
  final String email;
  final bool emailVerified;
  final UserRole role;

  User toEntity() =>
      User(id: id, email: email, emailVerified: emailVerified, role: role);
}
