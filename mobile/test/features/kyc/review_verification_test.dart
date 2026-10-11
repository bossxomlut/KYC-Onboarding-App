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
import 'package:kyc_onboarding/features/kyc/presentation/widgets/verification_summary.dart';

import 'kyc_cubit_test.dart' show FakeKycRepository;
import 'kyc_verification_test.dart'
    show readyProfile, completedJson, profileJson;

void main() {
  for (final provider in ['aws', 'local']) {
    for (final status in VerificationStatus.values) {
      testWidgets(
        '$provider ${status.name} hides technical checks from the applicant',
        (tester) async {
          final checks = completedJson()
            ..['provider'] = provider
            ..['status'] = switch (status) {
              VerificationStatus.disabled => 'disabled',
              VerificationStatus.notStarted => 'not_started',
              VerificationStatus.completed => 'completed',
              VerificationStatus.failed => 'failed',
            };
          final repository = _ReviewVerificationRepository()
            ..profile = KycProfileModel.fromJson(profileJson(checks));
          await _pumpReview(tester, repository);
          expect(find.byType(VerificationSummary), findsNothing);
          expect(find.byKey(const Key('run-identity-checks')), findsNothing);
          expect(find.textContaining('sent to AWS'), findsNothing);
          expect(
            find.textContaining('processed on the app server'),
            findsNothing,
          );
          expect(find.text('DEMO USER'), findsNothing);
          expect(find.text('Review & submit'), findsOneWidget);
          expect(find.text('Personal details'), findsOneWidget);
          expect(find.text('Demo User'), findsOneWidget);
          expect(find.text('ID document'), findsOneWidget);
          expect(find.text('Selfie'), findsOneWidget);
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

  testWidgets(
    'Submit runs checks without exposing a separate applicant action',
    (tester) async {
      final repository = _ReviewVerificationRepository();
      await _pumpReview(tester, repository);
      await tester.tap(find.byKey(const Key('submit-kyc')));
      await tester.pumpAndSettle();
      expect(repository.verificationCalls, 1);
      expect(repository.submitCalls, 1);
      expect(find.text('Status page'), findsOneWidget);
      expect(find.text('Identity checks'), findsNothing);
    },
  );

  testWidgets(
    'submission stays busy while checks run and prevents duplicate taps',
    (tester) async {
      final repository = _ReviewVerificationRepository()
        ..gate = Completer<Result<KycProfile>>();
      final cubit = await _pumpReview(tester, repository);
      final submit = find.byKey(const Key('submit-kyc'));
      await tester.tap(submit);
      await tester.pump();
      expect(cubit.state.operation, KycOperation.submitting);
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      expect(find.byKey(const Key('run-identity-checks')), findsNothing);
      expect(find.byType(VerificationSummary), findsNothing);
      expect(repository.verificationCalls, 1);
      expect(repository.submitCalls, 0);
      await tester.tap(submit);
      await tester.pump();
      expect(repository.verificationCalls, 1);
      repository.profile = readyProfile(VerificationStatus.completed);
      repository.gate!.complete(Success(repository.profile));
      await tester.pumpAndSettle();
      expect(repository.submitCalls, 1);
      expect(find.text('Status page'), findsOneWidget);
    },
  );
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
