import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kyc_onboarding/core/domain/result.dart';
import 'package:kyc_onboarding/core/theme/app_theme.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/capture_camera.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';
import 'package:kyc_onboarding/features/kyc/domain/repositories/capture_camera_repository.dart';
import 'package:kyc_onboarding/features/kyc/domain/usecases/capture_camera_usecases.dart';
import 'package:kyc_onboarding/features/kyc/domain/usecases/kyc_usecases.dart';
import 'package:kyc_onboarding/features/kyc/presentation/bloc/capture_camera_cubit.dart';
import 'package:kyc_onboarding/features/kyc/presentation/bloc/kyc_cubit.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/capture_page.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/in_app_camera_page.dart';
import 'package:kyc_onboarding/features/kyc/presentation/widgets/capture_camera_configuration.dart';

import 'capture_page_test.dart' show CaptureRepository;

void main() {
  testWidgets('repeated Open camera taps create a single camera session', (
    tester,
  ) async {
    final photos = CaptureRepository(MediaKind.document);
    final camera = _ReadyCamera();
    await _pump(tester, photos, camera);
    final open = tester
        .widget<FilledButton>(find.byKey(const Key('capture-document')))
        .onPressed!;
    open();
    open();
    await tester.pumpAndSettle();
    expect(camera.initializations, [MediaKind.document]);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(InAppCameraPage), findsNothing);
  });

  for (final kind in MediaKind.values) {
    testWidgets('${kind.name} opens camera before capture and cancels safely', (
      tester,
    ) async {
      final photos = CaptureRepository(kind);
      final camera = _ReadyCamera();
      await _pump(tester, photos, camera);
      expect(camera.initializations, isEmpty);
      await tester.tap(find.byKey(Key('capture-${kind.name}')));
      await tester.pumpAndSettle();
      expect(find.byType(InAppCameraPage), findsOneWidget);
      expect(camera.initializations, [kind]);
      expect(photos.captureCount, 0);
      expect(photos.uploadCount, 0);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(InAppCameraPage), findsNothing);
      expect(camera.closeCount, 1);
      expect(photos.captureCount, 0);
      expect(photos.uploadCount, 0);
    });

    testWidgets(
      '${kind.name} closes camera before upload and stays on preview',
      (tester) async {
        final photos = CaptureRepository(kind)..uploadGate = Completer<void>();
        final camera = _ReadyCamera();
        await _pump(tester, photos, camera);
        await tester.tap(find.byKey(Key('capture-${kind.name}')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('camera-shutter')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
        expect(find.byType(InAppCameraPage), findsNothing);
        expect(camera.closeCount, 1);
        expect(photos.captureCount, 1);
        expect(photos.uploadCount, 1);
        expect(find.byKey(Key('continue-${kind.name}')), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.byKey(Key('continue-${kind.name}')))
              .onPressed,
          isNull,
        );

        photos.uploadGate!.complete();
        await tester.pumpAndSettle();
        expect(find.text('Retake photo'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.byKey(Key('continue-${kind.name}')))
              .onPressed,
          isNotNull,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  CaptureRepository photos,
  _ReadyCamera camera,
) async {
  final cubit = KycCubit(
    loadKyc: LoadKyc(photos),
    savePersonalDetails: SavePersonalDetails(photos),
    captureMedia: CaptureMedia(photos),
    uploadMedia: UploadMedia(photos),
    loadPrivateMedia: LoadPrivateMedia(photos),
    submitKyc: SubmitKyc(photos),
    resubmitKyc: ResubmitKyc(photos),
    verifyIdentity: VerifyIdentity(photos),
    recoverCapture: RecoverCapture(photos),
    discardLocalMedia: DiscardLocalMedia(photos),
  );
  addTearDown(cubit.close);
  await cubit.load();
  final configuration = CaptureCameraConfiguration(
    createCubit: () => CaptureCameraCubit(
      initializeCamera: InitializeCaptureCamera(camera),
      setFlash: SetCaptureCameraFlash(camera),
      closeCamera: CloseCaptureCamera(camera),
    ),
    previewBuilder: (_) => const ColoredBox(color: Colors.black),
  );
  final router = GoRouter(
    initialLocation: photos.path,
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('Home')),
      ),
      GoRoute(
        path: photos.path,
        builder: (_, _) =>
            CapturePage(kind: photos.kind, camera: configuration),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    BlocProvider.value(
      value: cubit,
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

class _ReadyCamera implements CaptureCameraRepository {
  final initializations = <MediaKind>[];
  int closeCount = 0;
  @override
  Future<Result<CaptureCameraSession>> initialize(MediaKind kind) async {
    initializations.add(kind);
    return Success(CaptureCameraSession(kind: kind, aspectRatio: 3 / 4));
  }

  @override
  Future<Result<CaptureCameraSession>> setFlash(bool enabled) async => Success(
    CaptureCameraSession(kind: initializations.last, aspectRatio: 3 / 4),
  );

  @override
  Future<Result<void>> close() async {
    closeCount++;
    return const Success(null);
  }
}
