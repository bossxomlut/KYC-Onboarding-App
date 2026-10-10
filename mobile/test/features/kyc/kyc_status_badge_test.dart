import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';
import 'package:kyc_onboarding/features/kyc/presentation/widgets/kyc_status_badge.dart';

void main() {
  test('each status has a distinct readable foreground and icon', () {
    final appearances = KycStatus.values.map(KycStatusAppearance.forStatus);
    expect(appearances.map((value) => value.foreground).toSet(), hasLength(5));
    expect(appearances.map((value) => value.icon).toSet(), hasLength(5));
    for (final appearance in appearances) {
      final contrast =
          (appearance.background.computeLuminance() + .05) /
          (appearance.foreground.computeLuminance() + .05);
      expect(contrast, greaterThanOrEqualTo(4.5));
    }
  });

  for (final status in KycStatus.values) {
    testWidgets('${status.name} includes its label, icon and semantic status', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KycStatusBadge(
              status: status,
              labelKey: const Key('kyc-status'),
            ),
          ),
        ),
      );

      final appearance = KycStatusAppearance.forStatus(status);
      expect(find.text(status.label), findsOneWidget);
      expect(find.byKey(const Key('kyc-status')), findsOneWidget);
      expect(find.byIcon(appearance.icon), findsOneWidget);
      expect(
        find.bySemanticsLabel('Verification status: ${status.label}'),
        findsOneWidget,
      );
      expect(
        tester.widget<Text>(find.text(status.label)).style?.color,
        appearance.foreground,
      );
      expect(
        tester.widget<Icon>(find.byIcon(appearance.icon)).color,
        appearance.foreground,
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    testWidgets('${status.name} wraps on narrow screen with large text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: KycStatusBadge(status: status, prominent: true),
            ),
          ),
        ),
      );

      expect(find.text(status.label), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
