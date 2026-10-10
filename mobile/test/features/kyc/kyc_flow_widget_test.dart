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
import 'package:kyc_onboarding/features/kyc/presentation/pages/capture_page.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/home_page.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/personal_details_page.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/review_page.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/verification_page.dart';
import 'kyc_cubit_test.dart' show FakeKycRepository;

void main() {
  testWidgets(
    'home to submit: offline upload retry preserves saved details and captured image',
    (tester) async {
      final repository = FlowRepository();
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
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                HomePage(email: 'demo@example.test', onLogout: () async {}),
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
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('kyc-next')));
      await tester.tap(find.byKey(const Key('kyc-next')));
      await tester.pumpAndSettle();
      for (final entry in {
        'fullName': 'Demo User',
        'dateOfBirth': '1995-04-15',
        'nationality': 'Vietnamese',
        'address': '1 Demo Street',
        'documentNumber': 'DEMO1234',
      }.entries) {
        await tester.ensureVisible(find.byKey(Key(entry.key)));
        await tester.enterText(find.byKey(Key(entry.key)), entry.value);
      }
      await tester.ensureVisible(find.byKey(const Key('save-details')));
      await tester.tap(find.byKey(const Key('save-details')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('capture-document')));
      await tester.tap(find.byKey(const Key('capture-document')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('retry-upload')), findsOneWidget);
      expect(cubit.state.profile!.personalDetails!.fullName, 'Demo User');
      expect(cubit.state.pendingCaptures[MediaKind.document], isNotNull);
      await tester.ensureVisible(find.byKey(const Key('retry-upload')));
      await tester.tap(find.byKey(const Key('retry-upload')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('capture-selfie')));
      await tester.tap(find.byKey(const Key('capture-selfie')));
      await tester.pumpAndSettle();
      expect(find.text('Everything look right?'), findsOneWidget);
      expect(find.text('Demo User'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('submit-kyc')));
      await tester.tap(find.byKey(const Key('submit-kyc')));
      await tester.pumpAndSettle();
      expect(find.text('Pending review'), findsOneWidget);
      expect(cubit.state.pendingCaptures, isEmpty);
      expect(repository.captureCount, 2);
    },
  );
}

class FlowRepository extends FakeKycRepository {
  FlowRepository() {
    profile = const KycProfile(
      id: 'demo-profile',
      status: KycStatus.notStarted,
      nextStep: KycStep.personalDetails,
    );
  }
  PersonalDetails? details;
  KycMedia? document;
  KycMedia? selfie;
  bool firstUpload = true;
  final Uint8List image = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aSu8AAAAASUVORK5CYII=',
  );
  KycProfile _profile(
    KycStep step, {
    KycStatus status = KycStatus.inProgress,
  }) => KycProfile(
    id: 'demo-profile',
    status: status,
    nextStep: step,
    personalDetails: details,
    document: document,
    selfie: selfie,
  );
  @override
  Future<Result<KycProfile>> saveDetails(PersonalDetails value) async {
    details = value;
    profile = _profile(KycStep.document);
    return Success(profile);
  }

  @override
  Future<Result<CapturedMedia?>> capture(
    MediaKind kind,
    String profileId, {
    DocumentType? documentType,
  }) async {
    captureCount++;
    return Success(
      CapturedMedia(
        kind: kind,
        filePath: '/private/${kind.name}.png',
        bytes: image,
        documentType: documentType,
      ),
    );
  }

  @override
  Future<Result<KycProfile>> upload(
    CapturedMedia media, {
    void Function(int, int)? onProgress,
  }) async {
    if (firstUpload) {
      firstUpload = false;
      return const Failure(
        AppFailure(
          code: 'NETWORK_ERROR',
          message: 'Connection interrupted. Your photo is ready to retry.',
        ),
      );
    }
    onProgress?.call(1, 1);
    final metadata = KycMedia(
      id: media.kind.name,
      mimeType: 'image/png',
      size: image.length,
      documentType: media.documentType,
    );
    if (media.kind == MediaKind.document) {
      document = metadata;
    } else {
      selfie = metadata;
    }
    profile = _profile(selfie == null ? KycStep.selfie : KycStep.review);
    return Success(profile);
  }

  @override
  Future<Result<Uint8List>> privateMedia(MediaKind kind) async =>
      Success(image);
  @override
  Future<Result<KycProfile>> submit() async {
    profile = _profile(KycStep.result, status: KycStatus.pendingReview);
    return Success(profile);
  }
}
