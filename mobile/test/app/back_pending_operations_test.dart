import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/features/access/presentation/bloc/access_cubit.dart';
import 'package:kyc_onboarding/features/access/presentation/pages/reviewer_detail_page.dart';
import 'package:kyc_onboarding/features/auth/domain/entities/user.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';
import 'package:kyc_onboarding/features/kyc/presentation/bloc/kyc_cubit.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/home_page.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/personal_details_page.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/verification_page.dart';
import 'system_back_test.dart' show profileJson, pumpApp;

void main() {
  late int systemPopCount;
  setUp(() {
    systemPopCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemNavigator.pop') systemPopCount++;
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('saving details immediately after Back keeps the user at Home', (
    tester,
  ) async {
    final gate = Completer<void>();
    final (_, router) = await pumpApp(
      tester,
      location: '/kyc/details',
      operationGates: {'/kyc/personal-details': gate},
    );
    final pageContext = tester.element(find.byType(PersonalDetailsPage));
    final cubit = pageContext.read<KycCubit>();
    await tester.ensureVisible(find.byKey(const Key('save-details')));
    await tester.tap(find.byKey(const Key('save-details')));
    await tester.pump();
    expect(cubit.state.busy, isTrue);

    await tester.binding.handlePopRoute();
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(pageContext.mounted, isTrue);
    gate.complete();
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.byType(HomePage), findsOneWidget);
    expect(tester.element(find.byType(HomePage)).read<KycCubit>(), same(cubit));
    expect(cubit.state.profile!.nextStep, KycStep.document);
    expect(cubit.state.busy, isFalse);
    expect(cubit.isClosed, isFalse);
    expect(systemPopCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resubmitting immediately after Back keeps the user at Home', (
    tester,
  ) async {
    final gate = Completer<void>();
    final (_, router) = await pumpApp(
      tester,
      location: '/kyc/status',
      profile: {
        ...profileJson,
        'status': 'rejected',
        'nextStep': 'result',
        'rejectionReason': 'Please retake the identity document.',
        'requiredSteps': ['document'],
      },
      operationGates: {'/kyc/resubmit': gate},
    );
    final pageContext = tester.element(find.byType(VerificationPage));
    final cubit = pageContext.read<KycCubit>();
    await tester.ensureVisible(find.byKey(const Key('resubmit-kyc')));
    await tester.tap(find.byKey(const Key('resubmit-kyc')));
    await tester.pump();
    expect(cubit.state.busy, isTrue);

    await tester.binding.handlePopRoute();
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(pageContext.mounted, isTrue);
    gate.complete();
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.byType(HomePage), findsOneWidget);
    expect(tester.element(find.byType(HomePage)).read<KycCubit>(), same(cubit));
    expect(cubit.state.profile!.status, KycStatus.inProgress);
    expect(cubit.state.profile!.nextStep, KycStep.document);
    expect(cubit.state.busy, isFalse);
    expect(cubit.isClosed, isFalse);
    expect(systemPopCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('approving immediately after Back keeps the reviewer at Home', (
    tester,
  ) async {
    final gate = Completer<void>();
    final (_, router) = await pumpApp(
      tester,
      location: '/reviews/applicant',
      role: UserRole.reviewer,
      operationGates: {'/reviews/applicant/decision': gate},
    );
    final pageContext = tester.element(find.byType(ReviewerDetailPage));
    final cubit = pageContext.read<AccessCubit>();
    await tester.ensureVisible(find.byKey(const Key('review-approve')));
    await tester.tap(find.byKey(const Key('review-approve')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AlertDialog), findsNothing);
    expect(cubit.state.busy, isTrue);

    await tester.binding.handlePopRoute();
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(pageContext.mounted, isTrue);
    gate.complete();
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.byType(HomePage), findsOneWidget);
    expect(cubit.isClosed, isTrue);
    expect(systemPopCount, 0);
    expect(tester.takeException(), isNull);
  });
}
