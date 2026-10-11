import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kyc_onboarding/core/theme/app_theme.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';
import 'package:kyc_onboarding/features/kyc/domain/usecases/kyc_usecases.dart';
import 'package:kyc_onboarding/features/kyc/presentation/bloc/kyc_cubit.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/capture_page.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/home_page.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/personal_details_page.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/review_page.dart';

import 'kyc_cubit_test.dart' show FakeKycRepository;

const _details = PersonalDetails(
  fullName: 'Maya Demo',
  dateOfBirth: '1995-08-14',
  nationality: 'Vietnamese',
  address: '12 Example Street',
  documentNumber: 'DEMO123456',
);

const _profile = KycProfile(
  id: 'visual-profile',
  status: KycStatus.inProgress,
  nextStep: KycStep.document,
  personalDetails: _details,
);

void main() {
  testWidgets('Signature next-step card opens the server-selected step', (
    tester,
  ) async {
    await _pumpPage(tester, '/');
    await tester.tap(find.byKey(const Key('kyc-next-step')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('capture-document')), findsOneWidget);
    expect(find.byKey(const Key('save-details')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Signature next-step card reopens only requested corrections', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      '/',
      profile: const KycProfile(
        id: 'visual-profile',
        status: KycStatus.rejected,
        nextStep: KycStep.result,
        personalDetails: _details,
        requiredSteps: [KycStep.selfie],
        rejectionReason: 'Please provide a clearer selfie.',
      ),
    );
    await tester.tap(find.byKey(const Key('kyc-next-step')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('capture-selfie')), findsOneWidget);
    expect(find.byKey(const Key('capture-document')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('save action remains reachable above an open keyboard', (
    tester,
  ) async {
    await _pumpPage(tester, '/kyc/details');
    await tester.tap(find.byKey(const Key('fullName')));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    final save = find.byKey(const Key('save-details'));
    expect(tester.getRect(save).bottom, lessThanOrEqualTo(844 - 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'review submit action fills the same footer width as form actions',
    (tester) async {
      await _pumpPage(tester, '/kyc/review');
      expect(
        tester.getSize(find.byKey(const Key('submit-kyc'))).width,
        closeTo(390 - 44, .1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('requested corrections are not announced as completed tasks', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpPage(
      tester,
      '/',
      profile: const KycProfile(
        id: 'visual-profile',
        status: KycStatus.rejected,
        nextStep: KycStep.result,
        personalDetails: _details,
        requiredSteps: [KycStep.document, KycStep.selfie],
        rejectionReason: 'Please provide clearer photos.',
      ),
    );
    expect(
      find.bySemanticsLabel('ID document: Update required'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Selfie: Update required'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Personal details: Completed'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Review & submit: Submit after updates'),
      findsOneWidget,
    );
    expect(find.text('1/4'), findsOneWidget);
    expect(find.text('1 of 4 completed'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  for (final path in [
    '/',
    '/kyc/details',
    '/kyc/document',
    '/kyc/selfie',
    '/kyc/review',
  ]) {
    testWidgets('$path remains usable at 320px with doubled text', (
      tester,
    ) async {
      await _pumpPage(tester, path, size: const Size(320, 640), textScale: 2);
      expect(tester.takeException(), isNull);
      if (path == '/kyc/details') {
        await tester.ensureVisible(find.byKey(const Key('documentNumber')));
        await tester.enterText(
          find.byKey(const Key('documentNumber')),
          'DEMO9876',
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pumpPage(
  WidgetTester tester,
  String path, {
  KycProfile profile = _profile,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  final repository = FakeKycRepository()..profile = profile;
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
    initialLocation: path,
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) =>
            HomePage(email: 'demo@kyc.example', onLogout: () async {}),
      ),
      GoRoute(
        path: '/kyc/details',
        builder: (_, _) => const PersonalDetailsPage(),
      ),
      GoRoute(
        path: '/kyc/document',
        builder: (_, _) => const CapturePage(kind: MediaKind.document),
      ),
      GoRoute(
        path: '/kyc/selfie',
        builder: (_, _) => const CapturePage(kind: MediaKind.selfie),
      ),
      GoRoute(path: '/kyc/review', builder: (_, _) => const ReviewPage()),
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
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
