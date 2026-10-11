import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kyc_onboarding/core/domain/result.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';
import 'package:kyc_onboarding/features/kyc/domain/usecases/kyc_usecases.dart';
import 'package:kyc_onboarding/features/kyc/presentation/bloc/kyc_cubit.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/capture_page.dart';
import 'package:kyc_onboarding/features/kyc/presentation/widgets/kyc_scaffold.dart';
import 'kyc_cubit_test.dart' show FakeKycRepository;

void main() {
  testWidgets('document type selection preserves the Back navigation control', (
    tester,
  ) async {
    final repository = CaptureRepository(MediaKind.document);
    final (_, router) = await pumpCapture(tester, repository);
    expect(find.byTooltip('Back'), findsOneWidget);

    await tester.tap(find.byKey(const Key('document-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('National ID').last);
    await tester.pumpAndSettle();

    expect(find.text('National ID'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/');
    expect(find.text('Home destination'), findsOneWidget);
    expect(repository.captureCount, 0);
    expect(repository.uploadCount, 0);
  });

  for (final kind in MediaKind.values) {
    testWidgets(
      '${kind.name} uploaded photo without cached bytes is not reported as missing',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final repository = CaptureRepository(kind, uploaded: true);
          final (cubit, router) = await pumpCapture(tester, repository);

          expect(cubit.state.reviewMedia, isEmpty);
          expect(
            tester.widget<PrivatePhoto>(find.byType(PrivatePhoto)).bytes,
            isNull,
          );
          expect(find.text('Photo uploaded'), findsOneWidget);
          expect(find.text('No photo yet'), findsNothing);
          expect(
            find.bySemanticsLabel(
              kind == MediaKind.document
                  ? 'Document photo uploaded; preview unavailable'
                  : 'Selfie photo uploaded; preview unavailable',
            ),
            findsOneWidget,
          );
          expect(continueButton(tester, kind).onPressed, isNotNull);
          expect(router.state.uri.path, repository.path);
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets('${kind.name} waits for Continue after successful upload', (
      tester,
    ) async {
      final repository = CaptureRepository(kind)
        ..uploadGate = Completer<void>();
      final (cubit, router) = await pumpCapture(tester, repository);
      expect(continueButton(tester, kind).onPressed, isNull);
      await tapCapture(tester, kind);
      await tester.pump();
      expect(cubit.state.busy, isTrue);
      expect(continueButton(tester, kind).onPressed, isNull);
      expect(router.state.uri.path, repository.path);

      repository.uploadGate!.complete();
      await tester.pumpAndSettle();
      expect(router.state.uri.path, repository.path);
      expect(find.byKey(Key('capture-${kind.name}')), findsOneWidget);
      expect(find.text('Retake photo'), findsOneWidget);
      expect(cubit.state.pendingCaptures, isEmpty);
      expect(
        tester.widget<PrivatePhoto>(find.byType(PrivatePhoto)).bytes,
        repository.image,
      );
      expect(continueButton(tester, kind).onPressed, isNotNull);
      await tapContinue(tester, kind);
      expect(router.state.uri.path, repository.profile.nextStep.routePath);
      expect(repository.captureCount, 1);
      expect(repository.uploadCount, 1);
    });

    testWidgets('${kind.name} cancellation keeps Continue disabled', (
      tester,
    ) async {
      final repository = CaptureRepository(kind)..cancelCapture = true;
      final (_, router) = await pumpCapture(tester, repository);
      await tapCapture(tester, kind);
      await tester.pumpAndSettle();
      expect(continueButton(tester, kind).onPressed, isNull);
      expect(router.state.uri.path, repository.path);
      expect(repository.uploadCount, 0);
    });

    testWidgets(
      '${kind.name} failed retake blocks Continue until retry succeeds',
      (tester) async {
        final repository = CaptureRepository(kind, uploaded: true)
          ..uploadFailure = true;
        final (cubit, router) = await pumpCapture(tester, repository);
        expect(continueButton(tester, kind).onPressed, isNotNull);
        await tapCapture(tester, kind);
        await tester.pumpAndSettle();
        expect(cubit.state.pendingCaptures[kind], isNotNull);
        expect(continueButton(tester, kind).onPressed, isNull);
        expect(router.state.uri.path, repository.path);

        repository.uploadFailure = false;
        await tester.ensureVisible(find.byKey(const Key('retry-upload')));
        await tester.tap(find.byKey(const Key('retry-upload')));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, repository.path);
        expect(cubit.state.pendingCaptures, isEmpty);
        expect(continueButton(tester, kind).onPressed, isNotNull);
        await tapContinue(tester, kind);
        expect(router.state.uri.path, repository.profile.nextStep.routePath);
        expect(repository.captureCount, 1);
        expect(repository.uploadCount, 2);
      },
    );

    testWidgets('${kind.name} canceled retake preserves uploaded progress', (
      tester,
    ) async {
      final repository = CaptureRepository(kind, uploaded: true)
        ..cancelCapture = true;
      final (_, router) = await pumpCapture(tester, repository);
      await tapCapture(tester, kind);
      await tester.pumpAndSettle();
      expect(router.state.uri.path, repository.path);
      expect(continueButton(tester, kind).onPressed, isNotNull);
      await tapContinue(tester, kind);
      expect(router.state.uri.path, repository.profile.nextStep.routePath);
      expect(repository.uploadCount, 0);
    });
  }

  testWidgets(
    'editing an uploaded document continues to the server next step',
    (tester) async {
      final repository = CaptureRepository(MediaKind.document, uploaded: true)
        ..profile = const KycProfile(
          id: 'capture-profile',
          status: KycStatus.inProgress,
          nextStep: KycStep.review,
          document: uploadedPhoto,
          selfie: uploadedPhoto,
        );
      final (_, router) = await pumpCapture(tester, repository);
      await tapContinue(tester, MediaKind.document);
      expect(router.state.uri.path, '/kyc/review');
      expect(repository.captureCount, 0);
      expect(repository.uploadCount, 0);
    },
  );

  testWidgets('loading profile never announces opening the camera', (
    tester,
  ) async {
    final repository = CaptureRepository(MediaKind.document, uploaded: true);
    final (cubit, _) = await pumpCapture(tester, repository);
    repository.loadGate = Completer<void>();
    final reload = cubit.load();
    await tester.pump();
    expect(find.text('Opening camera…'), findsNothing);
    repository.loadGate!.complete();
    await reload;
    await tester.pumpAndSettle();
  });

  testWidgets('silent refresh preserves photo and explicit Continue', (
    tester,
  ) async {
    final repository = CaptureRepository(MediaKind.document);
    final (cubit, router) = await pumpCapture(tester, repository);
    await tapCapture(tester, MediaKind.document);
    await tester.pumpAndSettle();
    repository.loadGate = Completer<void>();
    final refresh = cubit.refresh();
    await tester.pump();
    expect(find.text('Opening camera…'), findsNothing);
    expect(continueButton(tester, MediaKind.document).onPressed, isNotNull);
    expect(
      tester.widget<PrivatePhoto>(find.byType(PrivatePhoto)).bytes,
      repository.image,
    );
    expect(router.state.uri.path, repository.path);
    repository.loadGate!.complete();
    await refresh;
    await tester.pumpAndSettle();
    expect(router.state.uri.path, repository.path);
    expect(repository.captureCount, 1);
    expect(repository.uploadCount, 1);
  });
}

FilledButton continueButton(WidgetTester tester, MediaKind kind) =>
    tester.widget<FilledButton>(find.byKey(Key('continue-${kind.name}')));

Future<void> tapCapture(WidgetTester tester, MediaKind kind) async {
  await tester.ensureVisible(find.byKey(Key('capture-${kind.name}')));
  await tester.tap(find.byKey(Key('capture-${kind.name}')));
}

Future<void> tapContinue(WidgetTester tester, MediaKind kind) async {
  await tester.ensureVisible(find.byKey(Key('continue-${kind.name}')));
  await tester.tap(find.byKey(Key('continue-${kind.name}')));
  await tester.pumpAndSettle();
}

Future<(KycCubit, GoRouter)> pumpCapture(
  WidgetTester tester,
  CaptureRepository repository,
) async {
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
    initialLocation: repository.path,
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('Home destination')),
      ),
      for (final kind in MediaKind.values)
        GoRoute(
          path: kind == MediaKind.document ? '/kyc/document' : '/kyc/selfie',
          builder: (_, _) => CapturePage(kind: kind),
        ),
      GoRoute(
        path: '/kyc/review',
        builder: (_, _) => const Scaffold(body: Text('Review destination')),
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
  return (cubit, router);
}

const uploadedPhoto = KycMedia(
  id: 'uploaded-photo',
  mimeType: 'image/png',
  size: 68,
  documentType: DocumentType.passport,
);

class CaptureRepository extends FakeKycRepository {
  CaptureRepository(this.kind, {bool uploaded = false}) {
    profile = KycProfile(
      id: 'capture-profile',
      status: KycStatus.inProgress,
      nextStep: uploaded
          ? nextStep
          : kind == MediaKind.document
          ? KycStep.document
          : KycStep.selfie,
      document: kind == MediaKind.selfie || uploaded ? uploadedPhoto : null,
      selfie: kind == MediaKind.selfie && uploaded ? uploadedPhoto : null,
    );
  }
  final MediaKind kind;
  bool cancelCapture = false;
  int uploadCount = 0;
  Completer<void>? uploadGate;
  Completer<void>? loadGate;
  final image = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aSu8AAAAASUVORK5CYII=',
  );
  String get path =>
      kind == MediaKind.document ? '/kyc/document' : '/kyc/selfie';
  KycStep get nextStep =>
      kind == MediaKind.document ? KycStep.selfie : KycStep.review;

  @override
  Future<Result<KycProfile>> load() async {
    if (loadGate != null) await loadGate!.future;
    return super.load();
  }

  @override
  Future<Result<CapturedMedia?>> capture(
    MediaKind kind,
    String profileId, {
    DocumentType? documentType,
  }) async {
    captureCount++;
    return Success(
      cancelCapture
          ? null
          : CapturedMedia(
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
    uploadCount++;
    if (uploadGate != null) await uploadGate!.future;
    if (uploadFailure) {
      return const Failure(
        AppFailure(code: 'NETWORK_ERROR', message: 'Connection interrupted.'),
      );
    }
    profile = KycProfile(
      id: profile.id,
      status: KycStatus.inProgress,
      nextStep: nextStep,
      document: kind == MediaKind.document ? uploadedPhoto : profile.document,
      selfie: kind == MediaKind.selfie ? uploadedPhoto : profile.selfie,
    );
    return Success(profile);
  }
}
