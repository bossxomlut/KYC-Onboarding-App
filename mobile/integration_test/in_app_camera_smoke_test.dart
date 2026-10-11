import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kyc_onboarding/core/theme/app_theme.dart';
import 'package:kyc_onboarding/features/kyc/data/datasources/camera_datasource.dart';
import 'package:kyc_onboarding/features/kyc/data/datasources/in_app_camera_driver.dart';
import 'package:kyc_onboarding/features/kyc/data/repositories/capture_camera_repository_impl.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';
import 'package:kyc_onboarding/features/kyc/domain/usecases/capture_camera_usecases.dart';
import 'package:kyc_onboarding/features/kyc/presentation/bloc/capture_camera_cubit.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/in_app_camera_page.dart';

/// Runs the production camera SDK, framing page and private capture storage.
/// It needs a device with both lenses, camera permission, and no API or account.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const previewSeconds = int.fromEnvironment(
    'CAMERA_SMOKE_PREVIEW_SECONDS',
    defaultValue: 4,
  );
  const nativeBackground = bool.fromEnvironment(
    'CAMERA_SMOKE_NATIVE_BACKGROUND',
  );

  for (final kind in MediaKind.values) {
    testWidgets(
      '${kind.name} real camera resumes, captures, and recovers private media',
      (tester) async {
        final driver = InAppCameraDriver();
        final source = InAppCameraDataSource(driver: driver);
        final repository = CaptureCameraRepositoryImpl(driver);
        final profileId = 'camera-smoke-${kind.name}';
        CaptureCameraCubit? camera;
        CapturedMedia? captured;
        bool? routeResult;

        await source.discard(profileId);
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: FilledButton(
                      key: const Key('open-smoke-camera'),
                      onPressed: () async {
                        routeResult = await Navigator.of(context).push<bool>(
                          MaterialPageRoute<bool>(
                            builder: (_) => BlocProvider<CaptureCameraCubit>(
                              create: (_) {
                                camera = CaptureCameraCubit(
                                  initializeCamera: InitializeCaptureCamera(
                                    repository,
                                  ),
                                  setFlash: SetCaptureCameraFlash(repository),
                                  closeCamera: CloseCaptureCamera(repository),
                                );
                                return camera!;
                              },
                              child: InAppCameraPage(
                                kind: kind,
                                documentType: kind == MediaKind.document
                                    ? DocumentType.passport
                                    : null,
                                previewBuilder: driver.buildPreview,
                                onCapture: () async {
                                  captured = await source.capture(
                                    kind,
                                    profileId,
                                    documentType: kind == MediaKind.document
                                        ? DocumentType.passport
                                        : null,
                                  );
                                  return captured != null;
                                },
                              ),
                            ),
                          ),
                        );
                      },
                      child: const Text('Open camera'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.byKey(const Key('open-smoke-camera')));
          await _waitUntil(
            tester,
            () => camera?.state.isReady == true,
            failure: () => camera?.state.failure?.message,
          );
          _expectLens(tester, kind);
          expect(
            find.byKey(
              Key(
                kind == MediaKind.document
                    ? 'document-camera-guide'
                    : 'selfie-camera-guide',
              ),
            ),
            findsOneWidget,
          );

          // A host can send Home / reopen the activity for a real background
          // cycle. The default dispatches equivalent lifecycle notifications.
          if (nativeBackground) {
            var observedPause = false;
            final lifecycle = camera!.stream.listen((state) {
              if (state.status == CaptureCameraStatus.paused) {
                observedPause = true;
              }
            });
            debugPrint('CAMERA_SMOKE_BACKGROUND_READY ${kind.name}');
            try {
              await _waitUntil(tester, () => observedPause);
            } finally {
              await lifecycle.cancel();
            }
          } else {
            binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
            binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
            expect(camera!.state.status, CaptureCameraStatus.paused);
            binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          }
          await _waitUntil(
            tester,
            () => camera!.state.isReady,
            failure: () => camera!.state.failure?.message,
          );
          _expectLens(tester, kind);

          // Keep the actual viewfinder visible briefly for adb screenshot QA.
          debugPrint('CAMERA_SMOKE_PREVIEW_READY ${kind.name}');
          for (var second = 0; second < previewSeconds; second++) {
            await tester.pump(const Duration(seconds: 1));
          }
          await tester.tap(find.byKey(const Key('camera-shutter')));
          await _waitUntil(tester, () => routeResult != null);
          expect(routeResult, isTrue);
          await _waitUntil(
            tester,
            () => find.byType(InAppCameraPage).evaluate().isEmpty,
          );
          expect(find.byType(InAppCameraPage), findsNothing);

          final photo = captured!;
          expect(photo.kind, kind);
          expect(photo.bytes, isNotEmpty);
          expect(photo.bytes.length, lessThanOrEqualTo(10 * 1024 * 1024));
          expect(photo.captureId, matches(RegExp(r'^[a-f0-9]{32}$')));
          expect(photo.filePath, contains('/kyc_captures/$profileId/'));
          expect(await File(photo.filePath).readAsBytes(), photo.bytes);
          expect(
            photo.documentType,
            kind == MediaKind.document ? DocumentType.passport : null,
          );

          await driver.close();
          final recovered = await source.recover(kind, profileId);
          expect(recovered, isNotNull);
          expect(recovered!.captureId, photo.captureId);
          expect(recovered.kind, kind);
          expect(recovered.filePath, photo.filePath);
          expect(recovered.bytes, photo.bytes);
          await source.remove(recovered);
          expect(await source.recover(kind, profileId), isNull);
          expect(await File(photo.filePath).exists(), isFalse);
          expect(tester.takeException(), isNull);
        } finally {
          binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          await tester.pumpWidget(const SizedBox.shrink());
          if (camera != null) await camera!.close();
          await driver.close();
          await source.discard(profileId);
        }
      },
    );
  }
}

void _expectLens(WidgetTester tester, MediaKind kind) {
  expect(find.byType(CameraPreview), findsOneWidget);
  final preview = tester.widget<CameraPreview>(find.byType(CameraPreview));
  expect(preview.controller.value.isInitialized, isTrue);
  expect(
    preview.controller.description.lensDirection,
    kind == MediaKind.document
        ? CameraLensDirection.back
        : CameraLensDirection.front,
  );
  expect(
    tester
        .widget<IconButton>(find.byKey(const Key('camera-shutter')))
        .onPressed,
    isNotNull,
  );
}

Future<void> _waitUntil(
  WidgetTester tester,
  bool Function() ready, {
  String? Function()? failure,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 40));
  while (!ready() && DateTime.now().isBefore(deadline)) {
    final error = failure?.call();
    if (error != null) fail(error);
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(ready(), isTrue, reason: 'Camera operation timed out.');
  await tester.pump(const Duration(milliseconds: 400));
}
