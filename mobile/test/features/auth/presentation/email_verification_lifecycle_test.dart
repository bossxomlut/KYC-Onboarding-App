import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/features/auth/domain/usecases/resend_verification_code.dart';
import 'package:kyc_onboarding/features/auth/domain/usecases/verify_email.dart';
import 'package:kyc_onboarding/features/auth/presentation/bloc/email_verification_cubit.dart';

import 'otp_code_field_test.dart' show VerificationRepository;

void main() {
  testWidgets('initial cooldown expires by elapsed time after suspension', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 10, 10);
    final repository = VerificationRepository();
    final cubit = EmailVerificationCubit(
      VerifyEmail(repository),
      ResendVerificationCode(repository),
      now: () => now,
    );
    addTearDown(cubit.close);
    cubit.startCooldown();
    expect(cubit.state.resendSeconds, 30);
    now = now.add(const Duration(seconds: 75));
    cubit.reconcileCooldown();
    expect(cubit.state.resendSeconds, 0);
    expect(repository.resendRequests, 0);
    await cubit.resend('demo@example.test');
    expect(repository.resendRequests, 1);
    expect(cubit.state.resendSeconds, 30);
    // Finish the timer inside the fake clock; stream disposal runs in teardown.
    now = now.add(const Duration(seconds: 30));
    cubit.reconcileCooldown();
    expect(cubit.state.resendSeconds, 0);
  });

  testWidgets(
    'resend cooldown recomputes instead of counting timer callbacks',
    (tester) async {
      var now = DateTime.utc(2026, 10, 10);
      final repository = VerificationRepository();
      final cubit = EmailVerificationCubit(
        VerifyEmail(repository),
        ResendVerificationCode(repository),
        now: () => now,
      );
      addTearDown(cubit.close);
      await cubit.resend('demo@example.test');
      now = now.add(const Duration(seconds: 20));
      await tester.pump(const Duration(seconds: 1));
      expect(cubit.state.resendSeconds, 10);
      await cubit.resend('demo@example.test');
      expect(repository.resendRequests, 1);
      now = now.add(const Duration(seconds: 10));
      cubit.reconcileCooldown();
      expect(cubit.state.resendSeconds, 0);
    },
  );
}
