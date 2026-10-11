import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kyc_onboarding/core/domain/result.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';
import 'package:kyc_onboarding/features/kyc/data/models/kyc_profile_model.dart';
import 'package:kyc_onboarding/features/kyc/domain/usecases/kyc_usecases.dart';
import 'package:kyc_onboarding/features/kyc/presentation/bloc/kyc_cubit.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/review_page.dart';

import 'kyc_cubit_test.dart' show FakeKycRepository;
import 'kyc_verification_test.dart'
    show readyProfile, completedJson, profileJson;

void main() {
  for (final sources in [
    {'documentId': 'older-document', 'selfieId': 'selfie'},
    {'documentId': 'document', 'selfieId': 'older-selfie'},
    {'documentId': null, 'selfieId': null},
  ]) {
    testWidgets(
      'changed or unknown sources $sources hide evidence and allow a fresh explicit check',
      (tester) async {
        final checks = completedJson()..addAll(sources);
        final repository = _ReviewVerificationRepository()
          ..profile = KycProfileModel.fromJson(profileJson(checks));
        final cubit = await _pumpReview(tester, repository);
        expect(find.text('DEMO USER'), findsNothing);
        expect(find.textContaining('Similarity score:'), findsNothing);
        expect(find.text('Recognized document text'), findsNothing);
        expect(
          find.text('Automated checks have not run for these photos yet.'),
          findsOneWidget,
        );
        final run = find.byKey(const Key('run-identity-checks'));
        expect(tester.widget<OutlinedButton>(run).onPressed, isNotNull);
        expect(repository.verificationCalls, 0);
        await tester.ensureVisible(run);
        await tester.tap(run);
        await tester.pumpAndSettle();
        expect(repository.verificationCalls, 1);
        expect(
          cubit.state.profile!.verification!.status,
          VerificationStatus.completed,
        );
        expect(cubit.state.profile!.personalDetails!.fullName, 'Demo User');
      },
    );
  }

  testWidgets(
    'checks explain AWS transfer and run only after explicit intent',
    (tester) async {
      final repository = _ReviewVerificationRepository();
      final cubit = await _pumpReview(tester, repository);
      expect(repository.verificationCalls, 0);
      expect(find.textContaining('sent to AWS'), findsOneWidget);
      final run = find.byKey(const Key('run-identity-checks'));
      await tester.ensureVisible(run);
      await tester.tap(run);
      await tester.pumpAndSettle();
      expect(repository.verificationCalls, 1);
      expect(cubit.state.profile!.status, KycStatus.inProgress);
      expect(find.byType(ReviewPage), findsOneWidget);
      expect(find.byKey(const Key('submit-kyc')), findsOneWidget);
      expect(run, findsNothing);
    },
  );

  testWidgets(
    'checking disables submission until completion and retains the page',
    (tester) async {
      final repository = _ReviewVerificationRepository()
        ..gate = Completer<Result<KycProfile>>();
      final cubit = await _pumpReview(tester, repository);
      final run = find.byKey(const Key('run-identity-checks'));
      await tester.ensureVisible(run);
      await tester.tap(run);
      await tester.pump();
      expect(cubit.state.operation, KycOperation.verifying);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('submit-kyc')))
            .onPressed,
        isNull,
      );
      expect(tester.widget<OutlinedButton>(run).onPressed, isNull);
      expect(find.text('Running identity checks…'), findsOneWidget);
      repository.profile = readyProfile(VerificationStatus.completed);
      repository.gate!.complete(Success(repository.profile));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('submit-kyc')))
            .onPressed,
        isNotNull,
      );
      expect(find.byType(ReviewPage), findsOneWidget);
      expect(repository.submitCalls, 0);
    },
  );

  testWidgets(
    'failed checks allow explicit retry and never replace personal details',
    (tester) async {
      final repository = _ReviewVerificationRepository()
        ..profile = readyProfile(VerificationStatus.failed);
      final cubit = await _pumpReview(tester, repository);
      final run = find.byKey(const Key('run-identity-checks'));
      expect(find.text('Retry identity checks'), findsOneWidget);
      await tester.ensureVisible(run);
      await tester.tap(run);
      await tester.pumpAndSettle();
      expect(repository.verificationCalls, 1);
      expect(cubit.state.profile!.personalDetails!.fullName, 'Demo User');
    },
  );

  for (final checks in [
    VerificationStatus.disabled,
    VerificationStatus.completed,
  ]) {
    testWidgets(
      '${checks.name} has no run action and manual submission remains enabled',
      (tester) async {
        final repository = _ReviewVerificationRepository()
          ..profile = readyProfile(checks);
        await _pumpReview(tester, repository);
        expect(find.byKey(const Key('run-identity-checks')), findsNothing);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('submit-kyc')))
              .onPressed,
          isNotNull,
        );
        expect(repository.verificationCalls, 0);
      },
    );
  }
}

Future<KycCubit> _pumpReview(
  WidgetTester tester,
  _ReviewVerificationRepository repository,
) async {
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
    initialLocation: '/kyc/review',
    routes: [
      GoRoute(path: '/kyc/review', builder: (_, _) => const ReviewPage()),
      GoRoute(
        path: '/kyc/status',
        builder: (_, _) => const Scaffold(body: Text('Status page')),
      ),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    router.dispose();
    await cubit.close();
  });
  await cubit.load();
  await tester.pumpWidget(
    BlocProvider.value(
      value: cubit,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return cubit;
}

class _ReviewVerificationRepository extends FakeKycRepository {
  _ReviewVerificationRepository() {
    profile = readyProfile(VerificationStatus.notStarted);
  }
  int verificationCalls = 0;
  int submitCalls = 0;
  Completer<Result<KycProfile>>? gate;
  @override
  Future<Result<KycProfile>> verifyIdentity() async {
    verificationCalls++;
    if (gate != null) return gate!.future;
    profile = readyProfile(VerificationStatus.completed);
    return Success(profile);
  }

  @override
  Future<Result<KycProfile>> submit() {
    submitCalls++;
    return super.submit();
  }

  @override
  Future<Result<Uint8List>> privateMedia(MediaKind kind) async => Success(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aSu8AAAAASUVORK5CYII=',
    ),
  );
}
