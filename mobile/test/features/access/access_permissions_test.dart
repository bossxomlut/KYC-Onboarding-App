import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/app/router/route_policy.dart';
import 'package:kyc_onboarding/features/auth/data/models/user_model.dart';
import 'package:kyc_onboarding/features/auth/domain/entities/user.dart';

void main() {
  test('missing and unknown server roles never grant permissions', () {
    for (final role in [null, 'owner', 'SUPER_ADMIN']) {
      final user = UserModel.fromJson({
        'id': 'u1',
        'email': 'sample@example.test',
        'emailVerified': true,
        'role': ?role,
      }).toEntity();
      expect(user.role, UserRole.user);
      expect(user.canReview, isFalse);
      expect(user.canManageUsers, isFalse);
    }
  });
  test('reviewers review and only super admin manages accounts', () {
    final reviewer = UserModel.fromJson({
      'id': 'r',
      'email': 'r@example.test',
      'emailVerified': true,
      'role': 'reviewer',
    }).toEntity();
    expect(reviewer.canReview, isTrue);
    expect(reviewer.canManageUsers, isFalse);
    final admin = UserModel.fromJson({
      'id': 'a',
      'email': 'a@example.test',
      'emailVerified': true,
      'role': 'super_admin',
    }).toEntity();
    expect(admin.canReview, isTrue);
    expect(admin.canManageUsers, isTrue);
    expect(admin, isNot(reviewer));
  });
  test(
    'privileged routes use current role and all users can request access',
    () {
      expect(
        RoutePolicy.redirect(
          access: SessionAccess.authenticated,
          location: '/admin',
          role: UserRole.user,
        ),
        '/access',
      );
      expect(
        RoutePolicy.redirect(
          access: SessionAccess.authenticated,
          location: '/admin',
          role: UserRole.reviewer,
        ),
        '/access',
      );
      expect(
        RoutePolicy.redirect(
          access: SessionAccess.authenticated,
          location: '/reviews/other',
          role: UserRole.user,
        ),
        '/access',
      );
      expect(
        RoutePolicy.redirect(
          access: SessionAccess.authenticated,
          location: '/reviews/other',
          role: UserRole.reviewer,
        ),
        isNull,
      );
      expect(
        RoutePolicy.redirect(
          access: SessionAccess.authenticated,
          location: '/admin',
          role: UserRole.superAdmin,
        ),
        isNull,
      );
      expect(
        RoutePolicy.redirect(
          access: SessionAccess.authenticated,
          location: '/access',
          role: UserRole.user,
        ),
        isNull,
      );
    },
  );
}
