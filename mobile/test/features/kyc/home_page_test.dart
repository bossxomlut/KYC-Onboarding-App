import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kyc_onboarding/core/domain/result.dart';
import 'package:kyc_onboarding/core/theme/app_theme.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';
import 'package:kyc_onboarding/features/kyc/domain/usecases/kyc_usecases.dart';
import 'package:kyc_onboarding/features/kyc/presentation/bloc/kyc_cubit.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/home_page.dart';

import 'kyc_cubit_test.dart' show FakeKycRepository;

const _reopenedProfile = KycProfile(
  id: 'home-profile',
  status: KycStatus.inProgress,
  nextStep: KycStep.selfie,
);

void main() {
  testWidgets(
    'Home resubmit completion preserves Account access during navigation',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _GatedResubmitRepository();
      final cubit = KycCubit(
        loadKyc: LoadKyc(repository),
        savePersonalDetails: SavePersonalDetails(repository),
        captureMedia: CaptureMedia(repository),
        uploadMedia: UploadMedia(repository),
        loadPrivateMedia: LoadPrivateMedia(repository),
        submitKyc: SubmitKyc(repository),
        resubmitKyc: ResubmitKyc(repository),
        recoverCapture: RecoverCapture(repository),
        discardLocalMedia: DiscardLocalMedia(repository),
      );
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                HomePage(email: 'demo@kyc.example', onLogout: () async {}),
          ),
          GoRoute(
            path: '/access',
            builder: (_, _) => const Scaffold(
              body: Text('Account access', key: Key('account-access-page')),
            ),
          ),
          GoRoute(
            path: '/kyc/selfie',
            builder: (_, _) =>
                const Scaffold(body: Text('Selfie', key: Key('selfie-page'))),
          ),
        ],
      );
      addTearDown(() async {
        router.dispose();
        await cubit.close();
        if (!repository.gate.isCompleted) {
          repository.gate.complete(_reopenedProfile);
        }
      });
      await cubit.load();
      await tester.pumpWidget(
        BlocProvider.value(
          value: cubit,
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final homeContext = tester.element(find.byType(HomePage));

      await tester.tap(find.byKey(const Key('kyc-next-step')));
      await tester.pump();
      expect(repository.resubmitCalls, 1);
      expect(cubit.state.busy, isTrue);
      expect(
        tester.widget<InkWell>(find.byKey(const Key('kyc-next-step'))).onTap,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('kyc-next')))
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const Key('account-access')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(router.routeInformationProvider.value.uri.path, '/access');
      expect(homeContext.mounted, isTrue);

      repository.gate.complete(_reopenedProfile);
      await tester.pumpAndSettle();

      expect(cubit.state.profile!.nextStep, KycStep.selfie);
      expect(cubit.state.busy, isFalse);
      expect(router.routeInformationProvider.value.uri.path, '/access');
      expect(find.byKey(const Key('account-access-page')), findsOneWidget);
      expect(find.byKey(const Key('selfie-page')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

class _GatedResubmitRepository extends FakeKycRepository {
  _GatedResubmitRepository() {
    profile = const KycProfile(
      id: 'home-profile',
      status: KycStatus.rejected,
      nextStep: KycStep.result,
      requiredSteps: [KycStep.selfie],
      rejectionReason: 'Please provide a clearer selfie.',
    );
  }

  final gate = Completer<KycProfile>();
  int resubmitCalls = 0;

  @override
  Future<Result<KycProfile>> resubmit() async {
    resubmitCalls++;
    profile = await gate.future;
    return Success(profile);
  }
}
