import 'user_model.dart';

final class AuthSessionModel {
  AuthSessionModel.fromJson(Map<String, dynamic> json)
      : user = UserModel.fromJson(json['user'] as Map<String, dynamic>),
        accessToken = json['accessToken'] as String,
        refreshToken = json['refreshToken'] as String;
  final UserModel user;
  final String accessToken;
  final String refreshToken;
}
