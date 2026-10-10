final class User {
  const User({
    required this.id,
    required this.email,
    required this.emailVerified,
  });
  final String id;
  final String email;
  final bool emailVerified;

  @override
  bool operator ==(Object other) =>
      other is User &&
      id == other.id &&
      email == other.email &&
      emailVerified == other.emailVerified;
  @override
  int get hashCode => Object.hash(id, email, emailVerified);
}
