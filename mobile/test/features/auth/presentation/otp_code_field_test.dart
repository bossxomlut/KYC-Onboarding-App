import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kyc_onboarding/core/domain/result.dart';
import 'package:kyc_onboarding/core/theme/app_theme.dart';
import 'package:kyc_onboarding/features/auth/domain/entities/user.dart';
import 'package:kyc_onboarding/features/auth/domain/repositories/auth_repository.dart';
import 'package:kyc_onboarding/features/auth/domain/usecases/resend_verification_code.dart';
import 'package:kyc_onboarding/features/auth/domain/usecases/verify_email.dart';
import 'package:kyc_onboarding/features/auth/presentation/bloc/email_verification_cubit.dart';
import 'package:kyc_onboarding/features/auth/presentation/pages/verify_email_page.dart';

class VerificationRepository implements AuthRepository {
  final verificationRequests = <({String email, String code})>[];
  Completer<Result<User>>? pendingVerification;
  int resendRequests = 0;

  @override
  Future<Result<User>> verifyEmail({
    required String email,
    required String code,
  }) async {
    verificationRequests.add((email: email, code: code));
    return pendingVerification == null
        ? const Success(
            User(id: '1', email: 'demo@example.test', emailVerified: true),
          )
        : await pendingVerification!.future;
  }

  @override
  Future<Result<void>> resendVerificationCode(String email) async {
    resendRequests++;
    return const Success(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Finder cell(int index) => find.byKey(ValueKey('otp-digit-$index'));

String digit(WidgetTester tester, int index) => tester
    .widget<Text>(find.descendant(of: cell(index), matching: find.byType(Text)))
    .data!;

Future<EmailVerificationCubit> showPage(
  WidgetTester tester,
  VerificationRepository repository, {
  void Function(User)? onSignedIn,
  double textScale = 1,
}) async {
  final cubit = EmailVerificationCubit(
    VerifyEmail(repository),
    ResendVerificationCode(repository),
  );
  addTearDown(cubit.close);
  await tester.pumpWidget(
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
        child: VerifyEmailPage(
          email: 'demo@example.test',
          onSignedIn: onSignedIn ?? (_) {},
        ),
      ),
    ),
  );
  return cubit;
}

void main() {
  testWidgets('renders six individual code cells and retains leading zero', (
    tester,
  ) async {
    await showPage(tester, VerificationRepository());
    for (var index = 0; index < 6; index++) {
      expect(cell(index), findsOneWidget);
    }
    await tester.enterText(find.byType(TextField), '012345');
    await tester.pump();
    expect(List.generate(6, (index) => digit(tester, index)), [
      '0',
      '1',
      '2',
      '3',
      '4',
      '5',
    ]);
  });

  testWidgets('pasted code filters digits and submits from keyboard', (
    tester,
  ) async {
    final repository = VerificationRepository();
    User? signedIn;
    await showPage(tester, repository, onSignedIn: (user) => signedIn = user);
    await tester.enterText(find.byType(TextField), 'Code: 01 23 45');
    await tester.pump();
    expect(List.generate(6, (index) => digit(tester, index)).join(), '012345');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(repository.verificationRequests, [
      (email: 'demo@example.test', code: '012345'),
    ]);
    expect(signedIn?.emailVerified, isTrue);
  });

  testWidgets('backspace and tapping a cell allow correction', (tester) async {
    await showPage(tester, VerificationRepository());
    await tester.enterText(find.byType(TextField), '012345');
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '01234',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();
    expect(digit(tester, 5), isEmpty);
    await tester.tapAt(tester.getCenter(cell(2)));
    await tester.pump();
    final input = tester.widget<TextField>(find.byType(TextField));
    expect(
      input.controller!.selection,
      const TextSelection(baseOffset: 2, extentOffset: 3),
    );
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '01934',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    await tester.pump();
    expect(digit(tester, 2), '9');
  });

  testWidgets('incomplete code validates and no request is sent', (
    tester,
  ) async {
    final repository = VerificationRepository();
    await showPage(tester, repository);
    await tester.enterText(find.byType(TextField), '123');
    await tester.tap(find.text('Verify email'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the six digit verification code.'), findsOneWidget);
    expect(repository.verificationRequests, isEmpty);
  });

  testWidgets('rapid taps select the latest code cell for correction', (
    tester,
  ) async {
    await showPage(tester, VerificationRepository());
    await tester.enterText(find.byType(TextField), '012345');
    await tester.pump();
    await tester.tapAt(tester.getCenter(cell(1)));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(tester.getCenter(cell(2)));
    await tester.pump();
    final input = tester.widget<TextField>(find.byType(TextField));
    expect(
      input.controller!.selection,
      const TextSelection(baseOffset: 2, extentOffset: 3),
    );
  });

  testWidgets('pasting a full code replaces existing digits at any cell', (
    tester,
  ) async {
    await showPage(tester, VerificationRepository());
    await tester.enterText(find.byType(TextField), '987654');
    await tester.pump();
    await tester.tapAt(tester.getCenter(cell(2)));
    await tester.pump();
    // Native paste replaces the selected digit while retaining prefix/suffix.
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '98Code: 01 23 45654',
        selection: TextSelection.collapsed(offset: 16),
      ),
    );
    await tester.pump();
    expect(List.generate(6, (index) => digit(tester, index)).join(), '012345');
  });

  testWidgets('verification disables editing and resend until it completes', (
    tester,
  ) async {
    final pending = Completer<Result<User>>();
    final repository = VerificationRepository()..pendingVerification = pending;
    await showPage(tester, repository);
    await tester.enterText(find.byType(TextField), '012345');
    await tester.tap(find.text('Verify email'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    await tester.tap(find.text('Resend verification code'));
    expect(repository.resendRequests, 0);
    pending.complete(
      const Failure(AppFailure(code: 'OTP_INVALID', message: 'Try again.')),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    expect(List.generate(6, (index) => digit(tester, index)).join(), '012345');
    expect(find.text('Try again.'), findsOneWidget);
  });

  testWidgets('six code cells fit a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await showPage(tester, VerificationRepository(), textScale: 2);
    await tester.enterText(find.byType(TextField), '012345');
    await tester.pump();
    expect(tester.takeException(), isNull);
    for (var index = 0; index < 6; index++) {
      expect(cell(index), findsOneWidget);
    }
  });
}
