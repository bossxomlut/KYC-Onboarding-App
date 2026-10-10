/// Pure navigation policy. The authenticated server profile controls progress.
enum SessionAccess {
  initializing,
  signedOut,
  verifyEmail,
  authenticated,
  connectionFailure,
}

abstract final class RoutePolicy {
  static const _public = {
    '/login',
    '/register',
    '/forgot-password',
    '/reset-password',
  };
  static const _steps = ['personal_details', 'document', 'selfie', 'review'];

  static String routeForStep(String step) => switch (step) {
    'personal_details' => '/kyc/details',
    'document' => '/kyc/document',
    'selfie' => '/kyc/selfie',
    'review' => '/kyc/review',
    _ => '/kyc/status',
  };

  static String? redirect({
    required SessionAccess access,
    required String location,
    String? kycStatus,
    String? nextStep,
  }) {
    switch (access) {
      case SessionAccess.initializing:
        if (location == '/reset-password') return null;
        return location == '/session' ? null : '/session';
      case SessionAccess.connectionFailure:
        if (location == '/reset-password') return null;
        return location == '/session' ? null : '/session';
      case SessionAccess.signedOut:
        return _public.contains(location) ? null : '/login';
      case SessionAccess.verifyEmail:
        return location == '/verify-email' ? null : '/verify-email';
      case SessionAccess.authenticated:
        if (location == '/reset-password') return null;
        if (_public.contains(location) ||
            location == '/verify-email' ||
            location == '/session') {
          return '/';
        }
    }
    if (location.startsWith('/kyc/') && location != '/kyc/status') {
      if (['pending_review', 'verified', 'rejected'].contains(kycStatus)) {
        return '/kyc/status';
      }
      if (nextStep != null) {
        final requested = _steps.indexWhere(
          (step) => routeForStep(step) == location,
        );
        final available = _steps.indexOf(nextStep);
        if (available >= 0 && requested > available) {
          return routeForStep(nextStep);
        }
      }
    }
    return null;
  }
}
