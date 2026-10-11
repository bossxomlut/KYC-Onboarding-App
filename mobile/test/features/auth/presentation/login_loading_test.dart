import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/core/domain/result.dart';
import 'package:kyc_onboarding/core/theme/app_theme.dart';
import 'package:kyc_onboarding/features/auth/domain/entities/user.dart';
import 'package:kyc_onboarding/features/auth/domain/repositories/auth_repository.dart';
import 'package:kyc_onboarding/features/auth/domain/usecases/login.dart';
import 'package:kyc_onboarding/features/auth/presentation/bloc/login_cubit.dart';
import 'package:kyc_onboarding/features/auth/presentation/pages/login_page.dart';

const _user = User(
  id: 'login-test-user',
  email: 'person@example.test',
  emailVerified: true,
);

class _PendingLoginRepository implements AuthRepository {
  final requests = <Completer<Result<User>>>[];

  @override
  Future<Result<User>> login({
    required String email,
    required String password,
  }) {
    final request = Completer<Result<User>>();
    requests.add(request);
    return request.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Finder _field(String label) => find.widgetWithText(TextFormField, label);

Future<void> _fillCredentials(WidgetTester tester) async {
  await tester.enterText(_field('Email'), _user.email);
  await tester.enterText(_field('Password'), 'Password1234');
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byType(FilledButton));
}

Future<void> _showLogin(
  WidgetTester tester,
  LoginCubit cubit, {
  double textScale = 1,
  void Function(User)? onSignedIn,
  void Function(String)? onVerificationRequired,
}) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: BlocProvider.value(
      value: cubit,
      child: LoginPage(
        onSignedIn: onSignedIn ?? (_) {},
        onVerificationRequired: onVerificationRequired ?? (_) {},
      ),
    ),
  ),
);

void main() {
  for (final textScale in [1.0, 2.0]) {
    testWidgets(
      'sign in keeps its layout and shows progress inside the button at text scale $textScale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = _PendingLoginRepository();
        final cubit = LoginCubit(Login(repository));
        addTearDown(cubit.close);
        User? signedIn;
        final semantics = tester.ensureSemantics();
        await _showLogin(
          tester,
          cubit,
          textScale: textScale,
          onSignedIn: (user) => signedIn = user,
        );
        await _fillCredentials(tester);
        final button = find.byType(FilledButton);
        final initialButtonRect = tester.getRect(button);
        final initialEmailRect = tester.getRect(_field('Email'));
        await tester.tap(button);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(tester.getRect(button), initialButtonRect);
        expect(tester.getRect(_field('Email')), initialEmailRect);
        expect(
          find.descendant(of: button, matching: find.text('Signing in…')),
          findsOneWidget,
        );
        final spinner = find.byType(CircularProgressIndicator);
        expect(find.descendant(of: button, matching: spinner), findsOneWidget);
        expect(
          tester.getRect(button).contains(tester.getCenter(spinner)),
          isTrue,
        );
        expect(
          tester.widget<CircularProgressIndicator>(spinner).color,
          AppTheme.light.colorScheme.onPrimary,
        );
        final busyButton = tester.widget<FilledButton>(button);
        expect(busyButton.onPressed, isNull);
        expect(
          busyButton.style?.backgroundColor?.resolve({WidgetState.disabled}),
          AppTheme.primary,
        );
        expect(find.bySemanticsLabel('Signing in…'), findsOneWidget);
        await tester.tap(button);
        await tester.pump();
        expect(repository.requests, hasLength(1));
        expect(signedIn, isNull);
        expect(tester.takeException(), isNull);

        repository.requests.single.complete(const Success(_user));
        await tester.pumpAndSettle();
        expect(signedIn, _user);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('Sign in'), findsOneWidget);
        expect(tester.getRect(button), initialButtonRect);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }

  testWidgets('failed sign in restores the button and allows retry', (
    tester,
  ) async {
    final repository = _PendingLoginRepository();
    final cubit = LoginCubit(Login(repository));
    addTearDown(cubit.close);
    String? verificationEmail;
    await _showLogin(
      tester,
      cubit,
      onVerificationRequired: (email) => verificationEmail = email,
    );
    await _fillCredentials(tester);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    repository.requests.single.complete(
      const Failure(
        AppFailure(
          code: 'INVALID_CREDENTIALS',
          message: 'Email or password is incorrect.',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Email or password is incorrect.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Sign in'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    for (final label in ['Email', 'Password']) {
      final input = tester.widget<TextField>(
        find.descendant(of: _field(label), matching: find.byType(TextField)),
      );
      expect(input.enabled, isTrue);
    }
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(repository.requests, hasLength(2));
    expect(find.text('Signing in…'), findsOneWidget);
    repository.requests.last.complete(
      const Failure(
        AppFailure(code: 'EMAIL_NOT_VERIFIED', message: 'Verify your email.'),
      ),
    );
    await tester.pumpAndSettle();
    expect(verificationEmail, _user.email);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
