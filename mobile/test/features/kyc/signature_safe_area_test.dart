import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kyc_onboarding/core/theme/app_theme.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';
import 'package:kyc_onboarding/features/kyc/domain/usecases/kyc_usecases.dart';
import 'package:kyc_onboarding/features/kyc/presentation/bloc/kyc_cubit.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/verification_page.dart';

import 'kyc_cubit_test.dart' show FakeKycRepository;

void main() {
  testWidgets(
    'Signature result action scrolls above the home-indicator inset',
    (tester) async {
      tester.view.physicalSize = const Size(390, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);

      final repository = FakeKycRepository()
        ..profile = const KycProfile(
          id: 'safe-area-profile',
          status: KycStatus.pendingReview,
          nextStep: KycStep.result,
        );
      final cubit = KycCubit(
        loadKyc: LoadKyc(repository),
        savePersonalDetails: SavePersonalDetails(repository),
        captureMedia: CaptureMedia(repository),
        uploadMedia: UploadMedia(repository),
        loadPrivateMedia: LoadPrivateMedia(repository),
        submitKyc: SubmitKyc(repository),
        resubmitKyc: ResubmitKyc(repository),
        verifyIdentity: VerifyIdentity(repository),
        recoverCapture: RecoverCapture(repository),
        discardLocalMedia: DiscardLocalMedia(repository),
      );
      final router = GoRouter(
        initialLocation: '/kyc/status',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('Home')),
          ),
          GoRoute(
            path: '/kyc/status',
            builder: (_, _) => const VerificationPage(),
          ),
        ],
      );
      addTearDown(() async {
        router.dispose();
        await cubit.close();
      });
      await cubit.load();
      await tester.pumpWidget(
        BlocProvider.value(
          value: cubit,
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final back = find.widgetWithText(TextButton, 'Back to home');
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -2000),
      );
      await tester.pumpAndSettle();

      final buttonRect = tester.getRect(back);
      expect(
        buttonRect.top,
        greaterThanOrEqualTo(tester.getRect(find.byType(AppBar)).bottom),
      );
      expect(buttonRect.bottom, lessThanOrEqualTo(640 - 34));
      expect(tester.takeException(), isNull);
    },
  );
}
