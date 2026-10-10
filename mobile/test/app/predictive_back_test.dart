import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/home_page.dart';
import 'system_back_test.dart' show pumpApp;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late bool? lastFrameworkHandlesBack;
  setUp(() {
    lastFrameworkHandlesBack = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
          lastFrameworkHandlesBack = call.arguments as bool;
        }
        return null;
      },
    );
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  const android = TargetPlatformVariant({TargetPlatform.android});
  testWidgets(
    'Android keeps Back in Flutter across KYC steps and releases it at Home',
    (tester) async {
      final (_, router) = await pumpApp(tester, location: '/kyc/details');
      expect(lastFrameworkHandlesBack, isTrue);

      router.go('/kyc/document');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/kyc/document');
      expect(lastFrameworkHandlesBack, isTrue);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(find.byType(HomePage), findsOneWidget);
      expect(lastFrameworkHandlesBack, isFalse);
    },
    variant: android,
  );

  testWidgets(
    'Android continues handling Back after dismissing a KYC bottom sheet',
    (tester) async {
      final (_, router) = await pumpApp(tester, location: '/kyc/details');
      await tester.ensureVisible(find.byKey(const Key('dateOfBirth')));
      await tester.tap(find.byKey(const Key('dateOfBirth')));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoDatePicker), findsOneWidget);
      expect(lastFrameworkHandlesBack, isTrue);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoDatePicker), findsNothing);
      expect(router.routeInformationProvider.value.uri.path, '/kyc/details');
      expect(lastFrameworkHandlesBack, isTrue);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(lastFrameworkHandlesBack, isFalse);
    },
    variant: android,
  );

  testWidgets(
    'Android handles KYC Back while the profile is still loading',
    (tester) async {
      final gate = Completer<void>();
      final (_, router) = await pumpApp(
        tester,
        location: '/kyc/document',
        loadGate: gate,
        settle: false,
      );
      expect(lastFrameworkHandlesBack, isTrue);

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(lastFrameworkHandlesBack, isFalse);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(HomePage), findsOneWidget);
      expect(lastFrameworkHandlesBack, isFalse);
      expect(tester.takeException(), isNull);
    },
    variant: android,
  );

  testWidgets('Android handles KYC Back after a profile load failure', (
    tester,
  ) async {
    final (_, router) = await pumpApp(
      tester,
      location: '/kyc/document',
      loadFailure: true,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(lastFrameworkHandlesBack, isTrue);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(lastFrameworkHandlesBack, isFalse);
    expect(tester.takeException(), isNull);
  }, variant: android);
}
