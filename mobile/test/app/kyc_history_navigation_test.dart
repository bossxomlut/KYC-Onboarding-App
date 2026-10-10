import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/app/router/route_policy.dart';
import 'package:kyc_onboarding/features/auth/domain/entities/user.dart';
import 'system_back_test.dart' show pumpApp, profileJson;

void main() {
  test('history stays accessible for every applicant profile status', () {
    for (final status in [
      'not_started',
      'in_progress',
      'pending_review',
      'verified',
      'rejected',
    ]) {
      expect(
        RoutePolicy.redirect(
          access: SessionAccess.authenticated,
          location: '/kyc/history',
          kycStatus: status,
          nextStep: status == 'in_progress' ? 'document' : 'result',
        ),
        isNull,
      );
    }
    expect(
      RoutePolicy.redirect(
        access: SessionAccess.signedOut,
        location: '/kyc/history',
      ),
      '/login',
    );
    expect(
      RoutePolicy.redirect(
        access: SessionAccess.authenticated,
        location: '/reviews/applicant/history',
        role: UserRole.user,
      ),
      '/access',
    );
  });

  testWidgets('Home exposes history while an applicant edits a resubmission', (
    tester,
  ) async {
    final (_, router) = await pumpApp(tester, location: '/');
    await tester.ensureVisible(find.byKey(const Key('view-kyc-history')));
    await tester.tap(find.byKey(const Key('view-kyc-history')));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/kyc/history');
    expect(find.text('Submission history'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(tester.takeException(), isNull);
  });

  testWidgets('rejected status exposes history before reopening the profile', (
    tester,
  ) async {
    final (_, router) = await pumpApp(
      tester,
      location: '/kyc/status',
      profile: {
        ...profileJson,
        'status': 'rejected',
        'nextStep': 'result',
        'rejectionReason': 'Document is unreadable',
        'requiredSteps': ['document'],
      },
    );
    await tester.ensureVisible(find.byKey(const Key('view-kyc-history')));
    await tester.tap(find.byKey(const Key('view-kyc-history')));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/kyc/history');
    expect(find.text('Submission history'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reviewer opens previous submissions for comparison', (
    tester,
  ) async {
    final (_, router) = await pumpApp(
      tester,
      location: '/reviews/applicant',
      role: UserRole.reviewer,
    );
    await tester.ensureVisible(find.byKey(const Key('view-applicant-history')));
    await tester.tap(find.byKey(const Key('view-applicant-history')));
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      '/reviews/applicant/history',
    );
    expect(find.text('Submission history'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(tester.takeException(), isNull);
  });

  testWidgets('history remains available when working profile loading fails', (
    tester,
  ) async {
    final (_, router) = await pumpApp(
      tester,
      location: '/kyc/history',
      loadFailure: true,
    );
    expect(router.routeInformationProvider.value.uri.path, '/kyc/history');
    expect(find.text('Submission history'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
