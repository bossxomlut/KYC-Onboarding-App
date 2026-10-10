enum UserRole {
  user('user', 'User'),
  reviewer('reviewer', 'Reviewer'),
  superAdmin('super_admin', 'Super admin');

  const UserRole(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static UserRole fromApi(Object? value) => switch (value) {
    'reviewer' => reviewer,
    'super_admin' => superAdmin,
    _ => user,
  };
}

final class User {
  const User({
    required this.id,
    required this.email,
    required this.emailVerified,
    this.role = UserRole.user,
  });
  final String id;
  final String email;
  final bool emailVerified;
  final UserRole role;
  bool get canReview => role == UserRole.reviewer || canManageUsers;
  bool get canManageUsers => role == UserRole.superAdmin;

  @override
  bool operator ==(Object other) =>
      other is User &&
      id == other.id &&
      email == other.email &&
      emailVerified == other.emailVerified &&
      role == other.role;
  @override
  int get hashCode => Object.hash(id, email, emailVerified, role);
}
