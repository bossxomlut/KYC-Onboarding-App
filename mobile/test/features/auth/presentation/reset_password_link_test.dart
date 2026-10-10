import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/core/domain/result.dart';
import 'package:kyc_onboarding/features/auth/domain/repositories/auth_repository.dart';
import 'package:kyc_onboarding/features/auth/domain/usecases/request_password_reset.dart';
import 'package:kyc_onboarding/features/auth/domain/usecases/reset_password.dart';
import 'package:kyc_onboarding/features/auth/presentation/bloc/auth_form_state.dart';
import 'package:kyc_onboarding/features/auth/presentation/bloc/password_reset_cubit.dart';
import 'package:kyc_onboarding/features/auth/presentation/pages/reset_password_page.dart';

class _ResetRepository implements AuthRepository {
  final pending = Completer<Result<void>>();
  String? submittedToken;
  @override
  Future<Result<void>> resetPassword({
    required String token,
    required String newPassword,
  }) {
    submittedToken = token;
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
  testWidgets(
    'new warm reset link replaces old token and clears password draft',
    (tester) async {
      final repository = _ResetRepository();
      final cubit = PasswordResetCubit(
        RequestPasswordReset(repository),
        ResetPassword(repository),
      );
      addTearDown(cubit.close);
      Future<void> show(String token) => tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(
            value: cubit,
            child: ResetPasswordPage(token: token),
          ),
        ),
      );
      await show('old-token');
      await tester.enterText(field('New password'), 'NewPassword1234');
      await tester.enterText(field('Confirm new password'), 'NewPassword1234');
      await show('new-token');
      expect(input(tester, 'Reset token').controller!.text, 'new-token');
      expect(input(tester, 'New password').controller!.text, isEmpty);
      expect(input(tester, 'Confirm new password').controller!.text, isEmpty);
    },
  );

  testWidgets('same-token rebuild preserves draft and pending operation', (
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
          child: const ResetPasswordPage(token: 'same-token'),
        ),
      ),
    );
    await show();
    await tester.enterText(field('New password'), 'NewPassword1234');
    await tester.enterText(field('Confirm new password'), 'NewPassword1234');
    await tester.ensureVisible(find.text('Change password'));
    await tester.tap(find.text('Change password'));
    await tester.pump();
    await show();
    expect(input(tester, 'New password').controller!.text, 'NewPassword1234');
    expect(cubit.state.isLoading, isTrue);
    expect(repository.submittedToken, 'same-token');
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
    Future<void> show(String token) => tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: ResetPasswordPage(token: token),
        ),
      ),
    );
    await show('old-token');
    final oldOperation = cubit.reset(
      token: 'old-token',
      newPassword: 'NewPassword1234',
    );
    await tester.pump();
    await show('new-token');
    repository.pending.complete(const Success(null));
    expect(await oldOperation, isTrue);
    await tester.pump();
    expect(cubit.state.status, AuthFormStatus.initial);
    expect(input(tester, 'Reset token').controller!.text, 'new-token');
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
    Future<void> show(String token, Future<void> Function() onReset) {
      return tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(
            value: cubit,
            child: ResetPasswordPage(token: token, onPasswordReset: onReset),
          ),
        ),
      );
    }

    await show('old-token', () async => oldCompletions++);
    await tester.enterText(field('New password'), 'NewPassword1234');
    await tester.enterText(field('Confirm new password'), 'NewPassword1234');
    await tester.ensureVisible(find.text('Change password'));
    await tester.tap(find.text('Change password'));
    await tester.pump();
    await show('new-token', () async => newCompletions++);
    repository.pending.complete(const Success(null));
    await tester.pumpAndSettle();
    expect(oldCompletions, 1);
    expect(newCompletions, 0);
    expect(cubit.state.status, AuthFormStatus.initial);
    expect(input(tester, 'Reset token').controller!.text, 'new-token');
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
            token: 'old-token',
            onPasswordReset: () async {
              completions++;
            },
          ),
        ),
      ),
    );
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
            token: 'old-token',
            onPasswordReset: () async {
              completions++;
            },
          ),
        ),
      ),
    );
    await tester.enterText(field('New password'), 'NewPassword1234');
    await tester.enterText(field('Confirm new password'), 'NewPassword1234');
    await tester.ensureVisible(find.text('Change password'));
    await tester.tap(find.text('Change password'));
    await tester.pump();
    repository.pending.complete(
      const Failure(
        AppFailure(code: 'RESET_TOKEN_INVALID', message: 'Request a new link.'),
      ),
    );
    await tester.pumpAndSettle();
    expect(completions, 0);
    expect(cubit.state.status, AuthFormStatus.failure);
  });
}
