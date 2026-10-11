import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/core/theme/app_theme.dart';
import 'package:kyc_onboarding/features/auth/domain/entities/user.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/home_page.dart';

import '../features/auth/data/session_restore_test.dart'
    show TestAdapter, jsonResponse, userJson;
import 'system_back_test.dart' show pumpApp;

void main() {
  testWidgets('reviewer Home action stays readable over the green header', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpApp(tester, location: '/', role: UserRole.reviewer);

    final button = find.byKey(const Key('review-profiles'));
    expect(button, findsOneWidget);
    final material = tester.widget<Material>(
      find.descendant(of: button, matching: find.byType(Material)),
    );
    final label = find.descendant(
      of: button,
      matching: find.text('Review profiles'),
    );
    final icon = find.descendant(
      of: button,
      matching: find.byIcon(Icons.fact_check_outlined),
    );
    final labelColor = DefaultTextStyle.of(tester.element(label)).style.color!;
    final iconColor = IconTheme.of(tester.element(icon)).color!;
    // The action overlaps the signature header; account for the actual button
    // surface rather than assuming the page's white scaffold is behind it.
    for (final headerColor in AppTheme.signatureGradient.colors) {
      final surface = Color.alphaBlend(
        material.color ?? Colors.transparent,
        headerColor,
      );
      expect(_contrast(labelColor, surface), greaterThanOrEqualTo(4.5));
      expect(_contrast(iconColor, surface), greaterThanOrEqualTo(4.5));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('newly granted reviewer opens the queue from Home and access', (
    tester,
  ) async {
    final (dependencies, router) = await pumpApp(tester, location: '/');
    final dio = dependencies<Dio>();
    final original = dio.httpClientAdapter;
    var role = 'user';
    var queueRequests = 0;
    dio.httpClientAdapter = TestAdapter((options) async {
      if (options.path == '/auth/me') {
        return jsonResponse({
          'user': {...userJson, 'role': role},
        });
      }
      if (options.path.split('?').first == '/reviews') queueRequests++;
      return original.fetch(options, null, null);
    });
    expect(find.byKey(const Key('review-profiles')), findsNothing);
    await tester.tap(find.byKey(const Key('account-access')));
    await tester.pumpAndSettle();
    expect(find.text('Current role: User'), findsOneWidget);

    // The admin grants permission while the applicant session remains open.
    role = 'reviewer';
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('Current role: Reviewer'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(tester.widget<HomePage>(find.byType(HomePage)).canReview, isTrue);
    await tester.tap(find.byKey(const Key('review-profiles')));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/reviews');
    expect(find.text('No profiles are waiting for review.'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/');

    await tester.tap(find.byKey(const Key('account-access')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review profiles'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/reviews');
    expect(queueRequests, 2);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/access');

    role = 'user';
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('Current role: User'), findsOneWidget);
    expect(find.text('Review profiles'), findsNothing);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/');
    expect(find.byKey(const Key('review-profiles')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

double _contrast(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + .05) / (darker + .05);
}
