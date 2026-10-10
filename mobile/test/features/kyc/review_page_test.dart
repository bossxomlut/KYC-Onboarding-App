import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kyc_onboarding/core/domain/result.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';
import 'package:kyc_onboarding/features/kyc/domain/usecases/kyc_usecases.dart';
import 'package:kyc_onboarding/features/kyc/presentation/bloc/kyc_cubit.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/review_page.dart';

import 'kyc_cubit_test.dart' show FakeKycRepository;

void main() {
  testWidgets('Review retries failed profile refresh without fetching photos', (
    tester,
  ) async {
    final repository = ReviewRepository();
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
    addTearDown(cubit.close);
    final router = GoRouter(
      initialLocation: '/kyc/review',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Scaffold()),
        GoRoute(path: '/kyc/review', builder: (_, _) => const ReviewPage()),
      ],
    );
    addTearDown(router.dispose);
    await cubit.load();
    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    final photoCalls = repository.photoCalls;
    repository.loadFailure = true;
    await cubit.refresh();
    await tester.pumpAndSettle();
    expect(repository.loadCalls, 2);
    repository.loadFailure = false;
    await tester.ensureVisible(find.text('Retry'));
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(repository.loadCalls, 3);
    expect(repository.photoCalls, photoCalls);
    expect(find.byKey(const Key('kyc-error')), findsNothing);
    expect(repository.submitCalls, 0);
    expect(repository.captureCount, 0);
  });
}

class ReviewRepository extends FakeKycRepository {
  ReviewRepository() {
    profile = const KycProfile(
      id: 'profile-demo',
      status: KycStatus.inProgress,
      nextStep: KycStep.review,
      document: KycMedia(id: 'document', mimeType: 'image/png', size: 68),
    );
  }
  int loadCalls = 0;
  int photoCalls = 0;
  int submitCalls = 0;
  @override
  Future<Result<KycProfile>> load() {
    loadCalls++;
    return super.load();
  }

  @override
  Future<Result<Uint8List>> privateMedia(MediaKind kind) async {
    photoCalls++;
    return Success(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aSu8AAAAASUVORK5CYII=',
      ),
    );
  }

  @override
  Future<Result<KycProfile>> submit() {
    submitCalls++;
    return super.submit();
  }
}
