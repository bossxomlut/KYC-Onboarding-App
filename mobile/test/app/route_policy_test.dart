import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/app/router/route_policy.dart';
import 'package:kyc_onboarding/features/auth/domain/entities/user.dart';

void main() {
  test('super admin returns home instead of entering applicant KYC routes', () {
    for (final location in [
      '/kyc/status',
      '/kyc/details',
      '/kyc/document',
      '/kyc/selfie',
      '/kyc/review',
    ]) {
      expect(
        RoutePolicy.redirect(
          access: SessionAccess.authenticated,
          location: location,
          role: UserRole.superAdmin,
        ),
        '/',
      );
      for (final role in [UserRole.user, UserRole.reviewer]) {
        expect(
          RoutePolicy.redirect(
            access: SessionAccess.authenticated,
            location: location,
            role: role,
          ),
          isNull,
        );
      }
    }
  });
  test('startup preserves password reset deep links', () {
    expect(
      RoutePolicy.redirect(
        access: SessionAccess.initializing,
        location: '/reset-password',
      ),
      isNull,
    );
  });
  test('protected flow requires authentication', () {
    expect(
      RoutePolicy.redirect(
        access: SessionAccess.signedOut,
        location: '/kyc/review',
      ),
      '/login',
    );
    expect(
      RoutePolicy.redirect(
        access: SessionAccess.signedOut,
        location: '/reset-password',
      ),
      isNull,
    );
  });
  test('restore network error stays retryable rather than signing out', () {
    expect(
      RoutePolicy.redirect(
        access: SessionAccess.connectionFailure,
        location: '/',
      ),
      '/session',
    );
    expect(
      RoutePolicy.redirect(
        access: SessionAccess.connectionFailure,
        location: '/session',
      ),
      isNull,
    );
  });
  test('unverified email is restricted to verification', () {
    expect(
      RoutePolicy.redirect(access: SessionAccess.verifyEmail, location: '/'),
      '/verify-email',
    );
    expect(
      RoutePolicy.redirect(
        access: SessionAccess.verifyEmail,
        location: '/verify-email',
      ),
      isNull,
    );
  });
  test('authenticated login redirects home and reset deep link is allowed', () {
    expect(
      RoutePolicy.redirect(
        access: SessionAccess.authenticated,
        location: '/login',
      ),
      '/',
    );
    expect(
      RoutePolicy.redirect(
        access: SessionAccess.authenticated,
        location: '/reset-password',
      ),
      isNull,
    );
  });
  test(
    'server next step controls resume and prevents skipping missing steps',
    () {
      expect(RoutePolicy.routeForStep('document'), '/kyc/document');
      expect(
        RoutePolicy.redirect(
          access: SessionAccess.authenticated,
          location: '/kyc/review',
          kycStatus: 'in_progress',
          nextStep: 'document',
        ),
        '/kyc/document',
      );
      expect(
        RoutePolicy.redirect(
          access: SessionAccess.authenticated,
          location: '/kyc/details',
          kycStatus: 'in_progress',
          nextStep: 'review',
        ),
        isNull,
      );
    },
  );
  test('pending and final profiles cannot open editing screens', () {
    for (final status in ['pending_review', 'verified', 'rejected']) {
      expect(
        RoutePolicy.redirect(
          access: SessionAccess.authenticated,
          location: '/kyc/details',
          kycStatus: status,
          nextStep: 'result',
        ),
        '/kyc/status',
      );
    }
  });
}
