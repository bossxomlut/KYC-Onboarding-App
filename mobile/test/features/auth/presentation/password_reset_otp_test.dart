import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/core/domain/result.dart';
import 'package:kyc_onboarding/core/theme/app_theme.dart';
import 'package:kyc_onboarding/features/auth/domain/repositories/auth_repository.dart';
import 'package:kyc_onboarding/features/auth/domain/usecases/request_password_reset.dart';
import 'package:kyc_onboarding/features/auth/domain/usecases/reset_password.dart';
import 'package:kyc_onboarding/features/auth/presentation/bloc/auth_form_state.dart';
import 'package:kyc_onboarding/features/auth/presentation/bloc/password_reset_cubit.dart';
import 'package:kyc_onboarding/features/auth/presentation/pages/reset_password_page.dart';

class _ResetRepository implements AuthRepository {
  final pending = Completer<Result<void>>();
  String? submittedEmail;
  String? submittedCode;
  String? submittedPassword;
  final requestedEmails = <String>[];
  Result<void> requestResult = const Success(null);
  Completer<Result<void>>? requestGate;
  @override
  Future<Result<void>> requestPasswordReset(String email) {
    requestedEmails.add(email);
    return requestGate?.future ?? Future.value(requestResult);
  }

  @override
  Future<Result<void>> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) {
    submittedEmail = email;
    submittedCode = code;
    submittedPassword = newPassword;
    return pending.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Finder field(String label) => find.widgetWithText(TextFormField, label);
TextField input(WidgetTester tester, String label) => tester.widget<TextField>(
  find.descendant(of: field(label), matching: find.byType(TextField)),
);

void main() {
  testWidgets('changing reset email clears OTP and password drafts', (
    tester,
  ) async {
    final repository = _ResetRepository();
    final cubit = PasswordResetCubit(
      RequestPasswordReset(repository),
      ResetPassword(repository),
    );
    addTearDown(cubit.close);
    Future<void> show(String email) => tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: ResetPasswordPage(email: email),
        ),
      ),
    );
    await show('old@example.test');
    await tester.enterText(find.byKey(const ValueKey('otp-input')), '012345');
    await tester.enterText(field('New password'), 'NewPassword1234');
    await tester.enterText(field('Confirm new password'), 'NewPassword1234');
    await show('new@example.test');
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('otp-input')))
          .controller!
          .text,
      isEmpty,
    );
    expect(input(tester, 'New password').controller!.text, isEmpty);
    expect(input(tester, 'Confirm new password').controller!.text, isEmpty);
  });

  testWidgets('same-email rebuild preserves draft and pending operation', (
    tester,
  ) async {
    final repository = _ResetRepository();
    final cubit = PasswordResetCubit(
      RequestPasswordReset(repository),
      ResetPassword(repository),
    );
    addTearDown(cubit.close);
    Future<void> show() => tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: const ResetPasswordPage(email: 'same@example.test'),
        ),
      ),
    );
    await show();
    await tester.enterText(find.byKey(const ValueKey('otp-input')), '012345');
    await tester.enterText(field('New password'), 'NewPassword1234');
    await tester.enterText(field('Confirm new password'), 'NewPassword1234');
    await tester.ensureVisible(find.text('Change password'));
    await tester.tap(find.text('Change password'));
    await tester.pump();
    await show();
    expect(input(tester, 'New password').controller!.text, 'NewPassword1234');
    expect(cubit.state.isLoading, isTrue);
    expect(repository.submittedEmail, 'same@example.test');
    expect(repository.submittedCode, '012345');
    repository.pending.complete(const Success(null));
    await tester.pumpAndSettle();
    expect(cubit.state.status, AuthFormStatus.success);
  });

  testWidgets('old reset completion cannot change a newly opened reset form', (
    tester,
  ) async {
    final repository = _ResetRepository();
    final cubit = PasswordResetCubit(
      RequestPasswordReset(repository),
      ResetPassword(repository),
    );
    addTearDown(cubit.close);
    Future<void> show(String email) => tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: ResetPasswordPage(email: email),
        ),
      ),
    );
    await show('old@example.test');
    final oldOperation = cubit.reset(
      email: 'old@example.test',
      code: '012345',
      newPassword: 'NewPassword1234',
    );
    await tester.pump();
    await show('new@example.test');
    repository.pending.complete(const Success(null));
    expect(await oldOperation, isTrue);
    await tester.pump();
    expect(cubit.state.status, AuthFormStatus.initial);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('otp-input')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('obsolete reset success still invokes the captured completion', (
    tester,
  ) async {
    final repository = _ResetRepository();
    final cubit = PasswordResetCubit(
      RequestPasswordReset(repository),
      ResetPassword(repository),
    );
    addTearDown(cubit.close);
    var oldCompletions = 0;
    var newCompletions = 0;
    Future<void> show(String email, Future<void> Function() onReset) {
      return tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(
            value: cubit,
            child: ResetPasswordPage(email: email, onPasswordReset: onReset),
          ),
        ),
      );
    }

    await show('old@example.test', () async => oldCompletions++);
    await tester.enterText(find.byKey(const ValueKey('otp-input')), '012345');
    await tester.enterText(field('New password'), 'NewPassword1234');
    await tester.enterText(field('Confirm new password'), 'NewPassword1234');
    await tester.ensureVisible(find.text('Change password'));
    await tester.tap(find.text('Change password'));
    await tester.pump();
    await show('new@example.test', () async => newCompletions++);
    repository.pending.complete(const Success(null));
    await tester.pumpAndSettle();
    expect(oldCompletions, 1);
    expect(newCompletions, 0);
    expect(cubit.state.status, AuthFormStatus.initial);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('otp-input')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('successful reset reports completion after page disposal', (
    tester,
  ) async {
    final repository = _ResetRepository();
    final cubit = PasswordResetCubit(
      RequestPasswordReset(repository),
      ResetPassword(repository),
    );
    var completions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider(
          create: (_) => cubit,
          child: ResetPasswordPage(
            email: 'old@example.test',
            onPasswordReset: () async {
              completions++;
            },
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('otp-input')), '012345');
    await tester.enterText(field('New password'), 'NewPassword1234');
    await tester.enterText(field('Confirm new password'), 'NewPassword1234');
    await tester.ensureVisible(find.text('Change password'));
    await tester.tap(find.text('Change password'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    expect(cubit.isClosed, isTrue);
    repository.pending.complete(const Success(null));
    await tester.pumpAndSettle();
    expect(completions, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed reset never invokes successful completion', (
    tester,
  ) async {
    final repository = _ResetRepository();
    final cubit = PasswordResetCubit(
      RequestPasswordReset(repository),
      ResetPassword(repository),
    );
    addTearDown(cubit.close);
    var completions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: ResetPasswordPage(
            email: 'old@example.test',
            onPasswordReset: () async {
              completions++;
            },
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('otp-input')), '012345');
    await tester.enterText(field('New password'), 'NewPassword1234');
    await tester.enterText(field('Confirm new password'), 'NewPassword1234');
    await tester.ensureVisible(find.text('Change password'));
    await tester.tap(find.text('Change password'));
    await tester.pump();
    repository.pending.complete(
      const Failure(
        AppFailure(code: 'RESET_OTP_INVALID', message: 'Request a new code.'),
      ),
    );
    await tester.pumpAndSettle();
    expect(completions, 0);
    expect(cubit.state.status, AuthFormStatus.failure);
    expect(input(tester, 'New password').controller!.text, 'NewPassword1234');
    expect(
      input(tester, 'Confirm new password').controller!.text,
      'NewPassword1234',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('otp-input')))
          .controller!
          .text,
      '012345',
    );
  });

  testWidgets('reset requires six digits and matching valid passwords', (
    tester,
  ) async {
    final repository = _ResetRepository();
    final cubit = PasswordResetCubit(
      RequestPasswordReset(repository),
      ResetPassword(repository),
    );
    addTearDown(cubit.close);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: const ResetPasswordPage(email: 'demo@example.test'),
        ),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('otp-input')), '12345');
    await tester.enterText(field('New password'), 'NewPassword1234');
    await tester.enterText(field('Confirm new password'), 'DoesNotMatch123');
    await tester.ensureVisible(find.text('Change password'));
    await tester.tap(find.text('Change password'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the six digit verification code.'), findsOneWidget);
    expect(find.text('Passwords must match.'), findsOneWidget);
    expect(repository.submittedCode, isNull);
    await tester.enterText(find.byKey(const ValueKey('otp-input')), '012345');
    await tester.enterText(field('New password'), 'short');
    await tester.enterText(field('Confirm new password'), 'short');
    await tester.ensureVisible(find.text('Change password'));
    await tester.tap(find.text('Change password'));
    await tester.pumpAndSettle();
    expect(find.text('Use 12–128 characters.'), findsOneWidget);
    expect(repository.submittedCode, isNull);
  });

  testWidgets('resend keeps drafts and blocks reset and duplicate requests', (
    tester,
  ) async {
    final repository = _ResetRepository()
      ..requestGate = Completer<Result<void>>();
    final cubit = PasswordResetCubit(
      RequestPasswordReset(repository),
      ResetPassword(repository),
    );
    addTearDown(cubit.close);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: const ResetPasswordPage(email: 'demo@example.test'),
        ),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('otp-input')), '012345');
    await tester.enterText(field('New password'), 'NewPassword1234');
    await tester.enterText(field('Confirm new password'), 'NewPassword1234');
    await tester.ensureVisible(find.text('Resend reset code'));
    await tester.tap(find.text('Resend reset code'));
    await tester.pump();
    expect(cubit.state.isResending, isTrue);
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('otp-input'))).enabled,
      isFalse,
    );
    await cubit.resend('demo@example.test');
    expect(
      await cubit.reset(
        email: 'demo@example.test',
        code: '012345',
        newPassword: 'NewPassword1234',
      ),
      isFalse,
    );
    expect(repository.requestedEmails, ['demo@example.test']);
    expect(repository.submittedCode, isNull);
    repository.requestGate!.complete(const Success(null));
    await tester.pumpAndSettle();
    expect(cubit.state.resendSeconds, greaterThan(0));
    expect(input(tester, 'New password').controller!.text, 'NewPassword1234');
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('otp-input')))
          .controller!
          .text,
      '012345',
    );
    await cubit.resend('demo@example.test');
    expect(repository.requestedEmails, ['demo@example.test']);
    cubit.resetForm();
  });

  testWidgets('failed resend allows retry without losing password or OTP', (
    tester,
  ) async {
    final repository = _ResetRepository()
      ..requestResult = const Failure(
        AppFailure(code: 'NETWORK', message: 'Try again.'),
      );
    final cubit = PasswordResetCubit(
      RequestPasswordReset(repository),
      ResetPassword(repository),
    );
    addTearDown(cubit.close);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: const ResetPasswordPage(email: 'demo@example.test'),
        ),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('otp-input')), '012345');
    await tester.enterText(field('New password'), 'NewPassword1234');
    await tester.enterText(field('Confirm new password'), 'NewPassword1234');
    await tester.ensureVisible(find.text('Resend reset code'));
    await tester.tap(find.text('Resend reset code'));
    await tester.pumpAndSettle();
    expect(cubit.state.resendSeconds, 0);
    expect(find.text('Try again.'), findsOneWidget);
    expect(input(tester, 'New password').controller!.text, 'NewPassword1234');
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('otp-input')))
          .controller!
          .text,
      '012345',
    );
    repository.requestResult = const Success(null);
    await tester.tap(find.text('Resend reset code'));
    await tester.pumpAndSettle();
    expect(repository.requestedEmails.length, 2);
    expect(cubit.state.resendSeconds, greaterThan(0));
    cubit.resetForm();
  });

  testWidgets('reset password hint wraps fully on narrow large-text screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _ResetRepository();
    final cubit = PasswordResetCubit(
      RequestPasswordReset(repository),
      ResetPassword(repository),
    );
    addTearDown(cubit.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: BlocProvider.value(
          value: cubit,
          child: const ResetPasswordPage(email: 'demo@example.test'),
        ),
      ),
    );
    await tester.ensureVisible(
      find.text('12–128 characters, uppercase, lowercase and a number'),
    );
    await tester.pumpAndSettle();
    final hint = tester.renderObject<RenderParagraph>(
      find.text('12–128 characters, uppercase, lowercase and a number'),
    );
    expect(hint.maxLines, isNull);
    expect(hint.didExceedMaxLines, isFalse);
    expect(hint.size.height, greaterThan(40));
    expect(hint.text.style!.color, AppTheme.muted);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reset resend deadline expires by elapsed time on resume', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 10, 11);
    final repository = _ResetRepository();
    final cubit = PasswordResetCubit(
      RequestPasswordReset(repository),
      ResetPassword(repository),
      now: () => now,
    );
    addTearDown(cubit.close);
    expect(await cubit.request(' Demo@Example.Test '), isTrue);
    expect(cubit.state.email, 'demo@example.test');
    expect(cubit.state.resendSeconds, 30);
    now = now.add(const Duration(seconds: 75));
    cubit.reconcileCooldown();
    expect(cubit.state.resendSeconds, 0);
    expect(repository.requestedEmails.length, 1);
    await cubit.resend('demo@example.test');
    expect(repository.requestedEmails.length, 2);
    expect(cubit.state.resendSeconds, 30);
    now = now.add(const Duration(seconds: 30));
    cubit.reconcileCooldown();
  });
}
