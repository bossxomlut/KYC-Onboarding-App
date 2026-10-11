import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:integration_test/integration_test.dart';
import 'package:kyc_onboarding/core/theme/app_theme.dart';
import 'package:kyc_onboarding/features/kyc/data/datasources/camera_datasource.dart';
import 'package:kyc_onboarding/features/kyc/data/datasources/in_app_camera_driver.dart';
import 'package:kyc_onboarding/features/kyc/data/repositories/capture_camera_repository_impl.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/camera_capture_crop.dart';
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
        final driver = _AuditedCameraDriver();
        final source = InAppCameraDataSource(driver: driver);
        final repository = CaptureCameraRepositoryImpl(driver);
        final profileId = 'camera-smoke-${kind.name}';
        CaptureCameraCubit? camera;
        CapturedMedia? captured;
        CameraCaptureCrop? captureCrop;
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
                                onCapture: (crop) async {
                                  captureCrop = crop;
                                  captured = await source.capture(
                                    kind,
                                    profileId,
                                    documentType: kind == MediaKind.document
                                        ? DocumentType.passport
                                        : null,
                                    crop: crop,
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
          final viewport = tester.getRect(
            find.byKey(const Key('capture-camera-preview-viewport')),
          );
          final guide = tester.getRect(
            find.byKey(
              Key(
                kind == MediaKind.document
                    ? 'document-camera-guide'
                    : 'selfie-camera-guide',
              ),
            ),
          );
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
          await _expectCaptureFraming(
            photo,
            driver.originalBytes!,
            captureCrop,
            {
              'devicePixelRatio': tester.view.devicePixelRatio,
              'viewport': _rectMetadata(viewport),
              'guide': _rectMetadata(guide),
            },
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

/// Intercepts only the real SDK's result for independent geometry verification.
class _AuditedCameraDriver extends InAppCameraDriver {
  Uint8List? originalBytes;

  @override
  Future<XFile> takePicture(MediaKind kind) async {
    final original = await super.takePicture(kind);
    originalBytes = await original.readAsBytes();
    return original;
  }
}

Future<void> _expectCaptureFraming(
  CapturedMedia photo,
  Uint8List originalBytes,
  CameraCaptureCrop? crop,
  Map<String, Object?> previewGeometry,
) async {
  final decodedOriginal = image.decodeImage(originalBytes);
  final decodedOutput = image.decodeImage(photo.bytes);
  expect(decodedOriginal, isNotNull);
  expect(decodedOutput, isNotNull);
  final original = image.bakeOrientation(decodedOriginal!);
  final output = image.bakeOrientation(decodedOutput!);
  expect(crop, isNotNull);
  final framing = crop!;
  expect(framing.marginFraction, .03);
  expect(framing.isPreviewMirrored, photo.kind == MediaKind.selfie);
  final imageAspect = original.width / original.height;
  // The preview and still can use different sensor aspect ratios. Find the
  // centered still-image region visible in the preview independently here.
  final previewWidth = imageAspect > framing.previewAspectRatio
      ? original.height * framing.previewAspectRatio
      : original.width.toDouble();
  final previewHeight = imageAspect > framing.previewAspectRatio
      ? original.height.toDouble()
      : original.width / framing.previewAspectRatio;
  // The front viewfinder is mirrored, while the upright original JPEG is not.
  // An off-center guide therefore refers to the opposite side of the sensor.
  final sourceLeft = framing.isPreviewMirrored
      ? 1 - framing.left - framing.width
      : framing.left;
  final frameLeft =
      (original.width - previewWidth) / 2 + sourceLeft * previewWidth;
  final frameTop =
      (original.height - previewHeight) / 2 + framing.top * previewHeight;
  final frameWidth = framing.width * previewWidth;
  final frameHeight = framing.height * previewHeight;
  final borderX = frameWidth * framing.marginFraction;
  final borderY = frameHeight * framing.marginFraction;
  final left = (frameLeft - borderX).clamp(0, original.width).floor();
  final top = (frameTop - borderY).clamp(0, original.height).floor();
  final right = (frameLeft + frameWidth + borderX)
      .clamp(0, original.width)
      .ceil();
  final bottom = (frameTop + frameHeight + borderY)
      .clamp(0, original.height)
      .ceil();
  expect(output.width, right - left);
  expect(output.height, bottom - top);
  expect(output.width, lessThan(original.width));
  expect(output.height, lessThan(original.height));
  expect(
    output.width / output.height,
    closeTo(photo.kind == MediaKind.document ? 1.42 : .74, .006),
  );

  debugPrint(
    'CAMERA_SMOKE_CAPTURE_RESULT ${photo.kind.name} '
    '${original.width}x${original.height} -> ${output.width}x${output.height}',
  );
  if (!const bool.fromEnvironment('CAMERA_SMOKE_SAVE_EVIDENCE')) return;
  // Opt in only when running against the emulator's synthetic camera scene.
  // The host can copy these files for visual QA without an account or API.
  final evidence = Directory(
    '${File(photo.filePath).parent.parent.parent.path}/camera-smoke-evidence',
  );
  await evidence.create(recursive: true);
  await File(
    '${evidence.path}/${photo.kind.name}-original.jpg',
  ).writeAsBytes(originalBytes);
  await File(
    '${evidence.path}/${photo.kind.name}-result.jpg',
  ).writeAsBytes(photo.bytes);
  await File('${evidence.path}/${photo.kind.name}.json').writeAsString(
    jsonEncode({
      'originalWidth': original.width,
      'originalHeight': original.height,
      'outputWidth': output.width,
      'outputHeight': output.height,
      'previewGeometry': previewGeometry,
      'crop': {
        'left': framing.left,
        'top': framing.top,
        'width': framing.width,
        'height': framing.height,
        'previewAspectRatio': framing.previewAspectRatio,
        'marginFraction': framing.marginFraction,
        'isPreviewMirrored': framing.isPreviewMirrored,
      },
    }),
  );
  debugPrint('CAMERA_SMOKE_EVIDENCE ${evidence.path}');
  // Flutter removes the test application when this run finishes. Leave a brief
  // opt-in window for the host to collect the synthetic camera artifacts.
  await Future<void>.delayed(const Duration(seconds: 5));
}

Map<String, double> _rectMetadata(Rect rect) => {
  'left': rect.left,
  'top': rect.top,
  'width': rect.width,
  'height': rect.height,
};

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
  if (const bool.fromEnvironment('CAMERA_SMOKE_SAVE_EVIDENCE')) {
    final rotations = tester
        .widgetList<RotatedBox>(
          find.descendant(
            of: find.byType(CameraPreview),
            matching: find.byType(RotatedBox),
          ),
        )
        .map((rotation) => rotation.quarterTurns)
        .toList();
    final transforms = tester
        .widgetList<Transform>(
          find.descendant(
            of: find.byType(CameraPreview),
            matching: find.byType(Transform),
          ),
        )
        .map(
          (transform) => [
            transform.transform.storage[0],
            transform.transform.storage[1],
            transform.transform.storage[4],
            transform.transform.storage[5],
          ],
        )
        .toList();
    debugPrint(
      'CAMERA_SMOKE_PREVIEW_TRANSFORMS ${kind.name} '
      '${jsonEncode({'deviceOrientation': preview.controller.value.deviceOrientation.name, 'lockedOrientation': preview.controller.value.lockedCaptureOrientation?.name, 'previewSize': preview.controller.value.previewSize.toString(), 'quarterTurns': rotations, 'transforms': transforms})}',
    );
  }
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
