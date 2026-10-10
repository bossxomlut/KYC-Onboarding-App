import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/app/di/dependencies.dart';
import 'package:kyc_onboarding/app/kyc_app.dart';
import 'package:kyc_onboarding/core/security/token_store.dart';

class EmptyTokenStore implements TokenStore {
  @override
  String? get accessToken => null;
  @override
  Future<String?> readRefreshToken() async => null;
  @override
  Future<void> saveTokens(
      {required String accessToken, required String refreshToken}) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  testWidgets('signed-out startup composes login and registration routes',
      (tester) async {
    final di = configureDependencies(tokens: EmptyTokenStore());
    await tester.pumpWidget(KycApp(dependencies: di));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
    await tester.tap(find.text('New here? Create an account'));
    await tester.pumpAndSettle();
    expect(
        find.widgetWithText(TextFormField, 'Confirm password'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await di.reset();
  });
}
