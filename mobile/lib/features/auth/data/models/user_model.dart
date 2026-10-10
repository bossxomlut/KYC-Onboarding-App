import '../../domain/entities/user.dart';

final class UserModel {
  UserModel.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        email = json['email'] as String,
        emailVerified = json['emailVerified'] as bool;
  final String id;
  final String email;
  final bool emailVerified;

  User toEntity() => User(id: id, email: email, emailVerified: emailVerified);
}
