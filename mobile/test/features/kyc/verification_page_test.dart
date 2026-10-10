import 'dart:async';
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
import 'package:kyc_onboarding/features/kyc/presentation/pages/verification_page.dart';
import 'package:kyc_onboarding/features/kyc/presentation/widgets/kyc_scaffold.dart';
import 'package:kyc_onboarding/features/kyc/presentation/widgets/kyc_status_badge.dart';

import 'kyc_cubit_test.dart' show FakeKycRepository;

void main() {
  for (final status in [
    KycStatus.pendingReview,
    KycStatus.verified,
    KycStatus.rejected,
  ]) {
    testWidgets(
      '${status.name} can preview submitted details and private photos without editing',
      (tester) async {
        final repository = SubmittedProfileRepository(status);
        final submitted = repository.profile;
        final cubit = await mountVerification(tester, repository);

        expect(find.text(status.label), findsOneWidget);
        expect(
          tester.widget<KycStatusBadge>(find.byType(KycStatusBadge)).status,
          status,
        );
        expect(find.text('View submitted profile'), findsOneWidget);
        expect(repository.privateMediaCalls, isEmpty);
        expect(
          find.byKey(const Key('resubmit-kyc')),
          status == KycStatus.rejected ? findsOneWidget : findsNothing,
        );

        await openPreview(tester);

        final sheet = find.byType(BottomSheet);
        expect(sheet, findsOneWidget);
        expect(inSheet(find.text('Submitted profile')), findsOneWidget);
        expect(
          tester
              .widget<KycStatusBadge>(inSheet(find.byType(KycStatusBadge)))
              .status,
          status,
        );
        for (final value in [
          'Demo User',
          '15 April 1995',
          'Vietnamese',
          '1 Demo Street',
          'DEMO1234',
          'Passport',
        ]) {
          expect(inSheet(find.text(value)), findsOneWidget);
        }
        expect(repository.privateMediaCalls, MediaKind.values);
        final photos = tester.widgetList<PrivatePhoto>(
          inSheet(find.byType(PrivatePhoto)),
        );
        expect(photos, hasLength(2));
        for (final photo in photos) {
          expect(photo.bytes, orderedEquals(tinyPng));
        }
        expect(
          tester
              .widgetList<Image>(inSheet(find.byType(Image)))
              .every((image) => image.image is MemoryImage),
          isTrue,
        );
        expect(inSheet(find.byType(Image)), findsNWidgets(2));
        expect(inSheet(find.byType(EditableText)), findsNothing);
        expect(inSheet(find.text('Edit')), findsNothing);
        expect(inSheet(find.byKey(const Key('submit-kyc'))), findsNothing);
        expect(inSheet(find.byKey(const Key('resubmit-kyc'))), findsNothing);
        expect(cubit.state.profile, same(submitted));
        expectNoMutations(repository);

        await tester.tap(find.byKey(const Key('close-submitted-profile')));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.text('Verification status'), findsOneWidget);
        expect(find.text(status.label), findsOneWidget);
        await tester.ensureVisible(find.byKey(const Key('refresh-status')));
        await tester.tap(find.byKey(const Key('refresh-status')));
        await tester.pumpAndSettle();
        expect(repository.loadCalls, 2);
        expect(cubit.state.profile, same(submitted));
        expectNoMutations(repository);
      },
    );
  }

  for (final status in [KycStatus.notStarted, KycStatus.inProgress]) {
    testWidgets('${status.name} has no submitted profile preview', (
      tester,
    ) async {
      final repository = SubmittedProfileRepository(status);
      await mountVerification(tester, repository);

      expect(
        tester.widget<KycStatusBadge>(find.byType(KycStatusBadge)).status,
        status,
      );
      expect(find.byKey(const Key('view-submitted-profile')), findsNothing);
      expect(repository.privateMediaCalls, isEmpty);
    });
  }

  testWidgets('status with no loaded profile has no submitted preview', (
    tester,
  ) async {
    final repository = SubmittedProfileRepository(KycStatus.pendingReview)
      ..loadFailure = true;
    final cubit = await mountVerification(tester, repository);

    expect(cubit.state.profile, isNull);
    expect(find.byKey(const Key('view-submitted-profile')), findsNothing);
    expect(repository.privateMediaCalls, isEmpty);
  });

  testWidgets('submitted details remain visible while private photos load', (
    tester,
  ) async {
    final document = Completer<Result<Uint8List>>();
    final repository = SubmittedProfileRepository(KycStatus.pendingReview)
      ..pendingDocument = document;
    final cubit = await mountVerification(tester, repository);

    await tester.ensureVisible(find.byKey(const Key('view-submitted-profile')));
    await tester.tap(find.byKey(const Key('view-submitted-profile')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(inSheet(find.text('Submitted profile')), findsOneWidget);
    expect(inSheet(find.text('Demo User')), findsOneWidget);
    expect(
      inSheet(find.byWidgetPredicate((widget) => widget is ProgressIndicator)),
      findsOneWidget,
    );
    expect(cubit.state.busy, isTrue);
    expectNoMutations(repository);

    document.complete(Success(tinyPng));
    await tester.pumpAndSettle();
    expect(cubit.state.busy, isFalse);
    expect(inSheet(find.byType(Image)), findsNWidgets(2));
  });

  testWidgets(
    'failed private photo can retry while preserving submitted data',
    (tester) async {
      final repository = SubmittedProfileRepository(KycStatus.pendingReview)
        ..failDocument = true;
      final submitted = repository.profile;
      final cubit = await mountVerification(tester, repository);
      await openPreview(tester);

      expect(inSheet(find.text('Demo User')), findsOneWidget);
      expect(inSheet(find.text('Photo service unavailable.')), findsOneWidget);
      expect(
        inSheet(find.byKey(const Key('retry-submitted-media'))),
        findsOneWidget,
      );
      expect(cubit.state.reviewMedia[MediaKind.document], isNull);
      expect(cubit.state.reviewMedia[MediaKind.selfie], orderedEquals(tinyPng));

      repository.failDocument = false;
      await tester.ensureVisible(
        find.byKey(const Key('retry-submitted-media')),
      );
      await tester.tap(find.byKey(const Key('retry-submitted-media')));
      await tester.pumpAndSettle();

      expect(inSheet(find.text('Photo service unavailable.')), findsNothing);
      expect(inSheet(find.byType(Image)), findsNWidgets(2));
      expect(repository.privateMediaCalls, [
        MediaKind.document,
        MediaKind.selfie,
        MediaKind.document,
        MediaKind.selfie,
      ]);
      expect(cubit.state.profile, same(submitted));
      expectNoMutations(repository);
    },
  );

  testWidgets('closing rejected preview keeps update and resubmit available', (
    tester,
  ) async {
    final repository = SubmittedProfileRepository(KycStatus.rejected);
    final cubit = await mountVerification(tester, repository);
    await openPreview(tester);
    await tester.tap(find.byKey(const Key('close-submitted-profile')));
    await tester.pumpAndSettle();

    expect(find.text('Document photo is blurry.'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('resubmit-kyc')));
    await tester.tap(find.byKey(const Key('resubmit-kyc')));
    await tester.pumpAndSettle();

    expect(repository.resubmitCalls, 1);
    expect(cubit.state.profile!.status, KycStatus.inProgress);
    expect(find.text('Selfie update'), findsOneWidget);
  });

  testWidgets('closing while photos load preserves the flow cubit', (
    tester,
  ) async {
    final document = Completer<Result<Uint8List>>();
    final repository = SubmittedProfileRepository(KycStatus.pendingReview)
      ..pendingDocument = document;
    final cubit = await mountVerification(tester, repository);

    await tester.ensureVisible(find.byKey(const Key('view-submitted-profile')));
    await tester.tap(find.byKey(const Key('view-submitted-profile')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(cubit.state.busy, isTrue);

    await tester.tap(find.byKey(const Key('close-submitted-profile')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(BottomSheet), findsNothing);
    expect(cubit.isClosed, isFalse);
    expect(find.text('Verification status'), findsOneWidget);

    document.complete(Success(tinyPng));
    await tester.pumpAndSettle();
    expect(cubit.isClosed, isFalse);
    expect(cubit.state.busy, isFalse);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('refresh-status')));
    await tester.tap(find.byKey(const Key('refresh-status')));
    await tester.pumpAndSettle();
    expect(repository.loadCalls, 2);
    expect(find.text('Pending review'), findsOneWidget);
    expectNoMutations(repository);
  });

  testWidgets('narrow screen with large text can scroll to selfie and close', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = SubmittedProfileRepository(KycStatus.pendingReview);
    final cubit = await mountVerification(
      tester,
      repository,
      textScaler: TextScaler.linear(2),
    );
    await openPreview(tester);

    final selfie = inSheet(
      find.byWidgetPredicate(
        (widget) =>
            widget is PrivatePhoto &&
            widget.label == 'Your private selfie photo',
      ),
    );
    await tester.ensureVisible(selfie);
    await tester.pumpAndSettle();
    expect(selfie.hitTestable(), findsOneWidget);
    expect(
      find.byKey(const Key('close-submitted-profile')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('close-submitted-profile')));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Verification status'), findsOneWidget);
    expect(cubit.isClosed, isFalse);
    expect(tester.takeException(), isNull);
    expectNoMutations(repository);
  });
}

Finder inSheet(Finder finder) =>
    find.descendant(of: find.byType(BottomSheet), matching: finder);

Future<void> openPreview(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('view-submitted-profile')));
  await tester.tap(find.byKey(const Key('view-submitted-profile')));
  await tester.pumpAndSettle();
}

Future<KycCubit> mountVerification(
  WidgetTester tester,
  SubmittedProfileRepository repository, {
  TextScaler? textScaler,
}) async {
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
    initialLocation: '/kyc/status',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold()),
      GoRoute(path: '/kyc/status', builder: (_, _) => const VerificationPage()),
      GoRoute(
        path: '/kyc/selfie',
        builder: (_, _) => const Scaffold(body: Text('Selfie update')),
      ),
    ],
  );
  addTearDown(() async {
    router.dispose();
    await cubit.close();
  });
  await tester.pumpWidget(
    BlocProvider.value(
      value: cubit,
      child: MaterialApp.router(
        routerConfig: router,
        builder: textScaler == null
            ? null
            : (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                child: child!,
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return cubit;
}

void expectNoMutations(SubmittedProfileRepository repository) {
  expect(repository.saved, isFalse);
  expect(repository.captureCount, 0);
  expect(repository.uploadCalls, 0);
  expect(repository.submitCalls, 0);
  expect(repository.resubmitCalls, 0);
}

final Uint8List tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aSu8AAAAASUVORK5CYII=',
);

class SubmittedProfileRepository extends FakeKycRepository {
  SubmittedProfileRepository(KycStatus status) {
    profile = KycProfile(
      id: 'submitted-demo',
      status: status,
      nextStep: KycStep.result,
      personalDetails: const PersonalDetails(
        fullName: 'Demo User',
        dateOfBirth: '1995-04-15',
        nationality: 'Vietnamese',
        address: '1 Demo Street',
        documentNumber: 'DEMO1234',
      ),
      document: KycMedia(
        id: 'document-demo',
        mimeType: 'image/png',
        size: tinyPng.length,
        documentType: DocumentType.passport,
      ),
      selfie: KycMedia(
        id: 'selfie-demo',
        mimeType: 'image/png',
        size: tinyPng.length,
      ),
      rejectionReason: status == KycStatus.rejected
          ? 'Document photo is blurry.'
          : null,
      requiredSteps: status == KycStatus.rejected
          ? const [KycStep.document]
          : const [],
      submittedAt: DateTime.utc(2026, 10, 9),
    );
  }

  final List<MediaKind> privateMediaCalls = [];
  int loadCalls = 0;
  int uploadCalls = 0;
  int submitCalls = 0;
  int resubmitCalls = 0;
  bool failDocument = false;
  Completer<Result<Uint8List>>? pendingDocument;

  @override
  Future<Result<KycProfile>> load() {
    loadCalls++;
    return super.load();
  }

  @override
  Future<Result<Uint8List>> privateMedia(MediaKind kind) async {
    privateMediaCalls.add(kind);
    if (kind == MediaKind.document) {
      if (pendingDocument != null) return pendingDocument!.future;
      if (failDocument) {
        return const Failure(
          AppFailure(
            code: 'NETWORK_ERROR',
            message: 'Photo service unavailable.',
          ),
        );
      }
    }
    return Success(tinyPng);
  }

  @override
  Future<Result<KycProfile>> upload(
    CapturedMedia media, {
    void Function(int, int)? onProgress,
  }) {
    uploadCalls++;
    return super.upload(media, onProgress: onProgress);
  }

  @override
  Future<Result<KycProfile>> submit() {
    submitCalls++;
    return super.submit();
  }

  @override
  Future<Result<KycProfile>> resubmit() {
    resubmitCalls++;
    return super.resubmit();
  }
}
