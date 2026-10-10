import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kyc_onboarding/core/domain/result.dart';
import 'package:kyc_onboarding/core/theme/app_theme.dart';
import 'package:kyc_onboarding/features/access/presentation/pages/admin_home_page.dart';
import 'package:kyc_onboarding/features/auth/domain/entities/user.dart';

const _admin = User(
  id: 'admin',
  email: 'admin@kyc.com',
  emailVerified: true,
  role: UserRole.superAdmin,
);

Future<void> _logout() async {}

void main() {
  testWidgets('admin home needs no KYC provider and shows management only', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AdminHomePage(user: _admin, onLogout: _logout),
      ),
    );

    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('Super admin'), findsOneWidget);
    expect(find.text('admin@kyc.com'), findsOneWidget);
    expect(find.text('Manage accounts'), findsOneWidget);
    expect(find.text('Review profiles'), findsOneWidget);
    expect(find.text('Your verification'), findsNothing);
    expect(find.text('VERIFICATION STATUS'), findsNothing);
    expect(find.text('Start verification'), findsNothing);
    expect(find.text('Personal details'), findsNothing);
    expect(find.byKey(const Key('kyc-status')), findsNothing);
    expect(find.byKey(const Key('kyc-next')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final destination in {
    'manage-accounts': ('/admin', 'Account management destination'),
    'review-profiles': ('/reviews', 'Reviewer destination'),
  }.entries) {
    testWidgets('admin action opens ${destination.value.$1}', (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => AdminHomePage(user: _admin, onLogout: _logout),
          ),
          GoRoute(
            path: destination.value.$1,
            builder: (_, _) => Scaffold(body: Text(destination.value.$2)),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      );
      await tester.tap(find.byKey(Key(destination.key)));
      await tester.pumpAndSettle();

      expect(find.text(destination.value.$2), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    });
  }

  testWidgets('sign out invokes the supplied session callback', (tester) async {
    var signOutCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AdminHomePage(user: _admin, onLogout: () async => signOutCalls++),
      ),
    );
    await tester.tap(find.byKey(const Key('logout')));
    await tester.pump();

    expect(signOutCalls, 1);
  });

  testWidgets('sign out is disabled while its session operation is running', (
    tester,
  ) async {
    var signOutCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AdminHomePage(
          user: _admin,
          isSigningOut: true,
          onLogout: () async => signOutCalls++,
        ),
      ),
    );

    expect(
      tester.widget<IconButton>(find.byKey(const Key('logout'))).onPressed,
      isNull,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byKey(const Key('logout')));
    await tester.pump();
    expect(signOutCalls, 0);
  });

  testWidgets('sign out failure stays visible on the admin home', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AdminHomePage(
          user: _admin,
          onLogout: _logout,
          error: const AppFailure(
            code: 'NETWORK_ERROR',
            message: 'Could not sign out. Please try again.',
          ),
        ),
      ),
    );
    expect(find.text('Could not sign out. Please try again.'), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byKey(const Key('logout'))).onPressed,
      isNotNull,
    );
  });

  testWidgets('admin home fits 320px with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: AdminHomePage(user: _admin, onLogout: _logout),
      ),
    );

    await tester.ensureVisible(find.byKey(const Key('review-profiles')));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Manage accounts'), findsOneWidget);
    expect(find.text('Review profiles'), findsOneWidget);
  });
}
