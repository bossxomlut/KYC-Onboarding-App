import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/core/domain/result.dart';
import 'package:kyc_onboarding/features/auth/domain/entities/user.dart';
import 'package:kyc_onboarding/features/auth/domain/repositories/auth_repository.dart';
import 'package:kyc_onboarding/features/auth/domain/usecases/login.dart';
import 'package:kyc_onboarding/features/auth/domain/usecases/register.dart';
import 'package:kyc_onboarding/features/auth/domain/usecases/request_password_reset.dart';
import 'package:kyc_onboarding/features/auth/domain/usecases/reset_password.dart';
import 'package:kyc_onboarding/features/auth/presentation/bloc/login_cubit.dart';
import 'package:kyc_onboarding/features/auth/presentation/bloc/password_reset_cubit.dart';
import 'package:kyc_onboarding/features/auth/presentation/bloc/register_cubit.dart';
import 'package:kyc_onboarding/features/auth/presentation/pages/login_page.dart';
import 'package:kyc_onboarding/features/auth/presentation/pages/register_page.dart';
import 'package:kyc_onboarding/features/auth/presentation/pages/reset_password_page.dart';

class _PendingAuthRepository implements AuthRepository {
  final accountResult = Completer<Result<User>>();
  final resetResult = Completer<Result<void>>();
  String? submittedEmail;
  String? submittedPassword;
  String? submittedToken;

  @override
  Future<Result<User>> login({
    required String email,
    required String password,
  }) {
    submittedEmail = email;
    submittedPassword = password;
    return accountResult.future;
  }

  @override
  Future<Result<User>> register({
    required String email,
    required String password,
  }) => login(email: email, password: password);

  @override
  Future<Result<void>> resetPassword({
    required String token,
    required String newPassword,
  }) {
    submittedToken = token;
    submittedPassword = newPassword;
    return resetResult.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Finder _field(String label) => find.widgetWithText(TextFormField, label);

TextField _textField(WidgetTester tester, String label) =>
    tester.widget<TextField>(
      find.descendant(of: _field(label), matching: find.byType(TextField)),
    );

IconButton _visibilityButton(WidgetTester tester, String tooltip) =>
    tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == tooltip,
      ),
    );

Future<void> _toggle(WidgetTester tester, String tooltip) async {
  await tester.ensureVisible(find.byTooltip(tooltip));
  await tester.tap(find.byTooltip(tooltip));
  await tester.pump();
}

void main() {
  testWidgets(
    'login shows and hides the password while preserving edit and submission',
    (tester) async {
      final repository = _PendingAuthRepository();
      final cubit = LoginCubit(Login(repository));
      addTearDown(cubit.close);
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(
            value: cubit,
            child: LoginPage(
              onSignedIn: (_) {},
              onVerificationRequired: (_) {},
            ),
          ),
        ),
      );
      expect(_textField(tester, 'Password').obscureText, isTrue);
      expect(_textField(tester, 'Password').autofillHints, [
        AutofillHints.password,
      ]);
      await tester.enterText(_field('Email'), 'person@example.com');
      await tester.enterText(_field('Password'), 'Password1234');
      final controller = _textField(tester, 'Password').controller!;
      controller.selection = const TextSelection.collapsed(offset: 4);
      final selection = controller.selection;
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Show password'), findsOneWidget);
      await _toggle(tester, 'Show password');
      expect(_textField(tester, 'Password').obscureText, isFalse);
      expect(controller.text, 'Password1234');
      expect(controller.selection, selection);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: _field('Password'),
                matching: find.byType(EditableText),
              ),
            )
            .focusNode
            .hasFocus,
        isTrue,
      );
      expect(find.bySemanticsLabel('Hide password'), findsOneWidget);
      await _toggle(tester, 'Hide password');
      expect(_textField(tester, 'Password').obscureText, isTrue);
      semantics.dispose();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(repository.submittedEmail, 'person@example.com');
      expect(repository.submittedPassword, 'Password1234');
      expect(_textField(tester, 'Password').enabled, isFalse);
      expect(_visibilityButton(tester, 'Show password').onPressed, isNull);
    },
  );

  testWidgets(
    'registration password toggles independently and confirmation still validates',
    (tester) async {
      final repository = _PendingAuthRepository();
      final cubit = RegisterCubit(Register(repository));
      addTearDown(cubit.close);
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(
            value: cubit,
            child: RegisterPage(onVerificationRequired: (_) {}),
          ),
        ),
      );
      expect(_textField(tester, 'Password').obscureText, isTrue);
      expect(_textField(tester, 'Confirm password').obscureText, isTrue);
      await tester.enterText(_field('Email'), 'person@example.com');
      await tester.enterText(_field('Password'), 'Password1234');
      await tester.enterText(_field('Confirm password'), 'Different1234');
      await _toggle(tester, 'Show password');
      expect(_textField(tester, 'Password').obscureText, isFalse);
      expect(_textField(tester, 'Confirm password').obscureText, isTrue);
      await tester.ensureVisible(find.text('Create account'));
      await tester.tap(find.text('Create account'));
      await tester.pump();
      expect(find.text('Passwords must match.'), findsOneWidget);
      expect(repository.submittedPassword, isNull);
      await tester.enterText(_field('Confirm password'), 'Password1234');
      await _toggle(tester, 'Show confirm password');
      expect(_textField(tester, 'Confirm password').obscureText, isFalse);
      expect(_textField(tester, 'Password').autofillHints, [
        AutofillHints.newPassword,
      ]);
      await tester.ensureVisible(find.text('Create account'));
      await tester.tap(find.text('Create account'));
      await tester.pump();
      expect(repository.submittedPassword, 'Password1234');
      for (final label in ['Password', 'Confirm password']) {
        expect(_textField(tester, label).enabled, isFalse);
      }
      for (final tooltip in ['Hide password', 'Hide confirm password']) {
        expect(_visibilityButton(tester, tooltip).onPressed, isNull);
      }
    },
  );

  testWidgets(
    'reset password toggles independently and keeps its token obscured',
    (tester) async {
      final repository = _PendingAuthRepository();
      final cubit = PasswordResetCubit(
        RequestPasswordReset(repository),
        ResetPassword(repository),
      );
      addTearDown(cubit.close);
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(
            value: cubit,
            child: const ResetPasswordPage(token: 'reset-token'),
          ),
        ),
      );
      expect(_textField(tester, 'New password').obscureText, isTrue);
      expect(_textField(tester, 'Confirm new password').obscureText, isTrue);
      await tester.enterText(_field('New password'), 'NewPassword1234');
      await tester.enterText(_field('Confirm new password'), 'NewPassword1234');
      await _toggle(tester, 'Show new password');
      expect(_textField(tester, 'New password').obscureText, isFalse);
      expect(_textField(tester, 'Confirm new password').obscureText, isTrue);
      await _toggle(tester, 'Show confirm new password');
      expect(_textField(tester, 'Confirm new password').obscureText, isFalse);
      expect(_textField(tester, 'Reset token').obscureText, isTrue);
      expect(find.byTooltip('Show reset token'), findsNothing);
      await tester.ensureVisible(find.text('Change password'));
      await tester.tap(find.text('Change password'));
      await tester.pump();
      expect(repository.submittedToken, 'reset-token');
      expect(repository.submittedPassword, 'NewPassword1234');
      for (final tooltip in [
        'Hide new password',
        'Hide confirm new password',
      ]) {
        expect(_visibilityButton(tester, tooltip).onPressed, isNull);
      }
    },
  );
}
