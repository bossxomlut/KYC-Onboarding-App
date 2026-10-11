import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/core/domain/result.dart';
import 'package:kyc_onboarding/core/theme/app_theme.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/capture_camera.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/document_capture_crop.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';
import 'package:kyc_onboarding/features/kyc/domain/repositories/capture_camera_repository.dart';
import 'package:kyc_onboarding/features/kyc/domain/usecases/capture_camera_usecases.dart';
import 'package:kyc_onboarding/features/kyc/presentation/bloc/capture_camera_cubit.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/in_app_camera_page.dart';

void main() {
  final displays = <({String label, Size size, double textScale})>[
    (label: 'portrait', size: const Size(390, 844), textScale: 1),
    (label: 'small with large text', size: const Size(320, 568), textScale: 2),
    (label: 'landscape', size: const Size(844, 390), textScale: 1),
  ];

  for (final display in displays) {
    testWidgets('document crop encloses the actual guide on ${display.label}', (
      tester,
    ) async {
      tester.view.physicalSize = display.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      DocumentCaptureCrop? capturedCrop;
      await _pumpCapture(
        tester,
        kind: MediaKind.document,
        textScale: display.textScale,
        onCapture: (crop) async {
          capturedCrop = crop;
          return false;
        },
      );

      final guide = tester.getRect(
        find.byKey(const Key('document-camera-guide')),
      );
      final viewport = tester.getRect(
        find.byKey(const Key('capture-camera-preview-viewport')),
      );
      await tester.tap(find.byKey(const Key('camera-shutter')));
      await tester.pumpAndSettle();

      expect(capturedCrop, isNotNull);
      final crop = capturedCrop!;
      // Convert the callback metadata back into screen coordinates, using
      // the actual preview viewport and the camera's upright aspect ratio.
      // This catches offsets from headers, safe areas and side controls.
      final scale = math.max(
        viewport.width / crop.previewAspectRatio,
        viewport.height,
      );
      final imageWidth = crop.previewAspectRatio * scale;
      final imageHeight = scale;
      final imageLeft = viewport.center.dx - imageWidth / 2;
      final imageTop = viewport.center.dy - imageHeight / 2;
      final mapped = Rect.fromLTWH(
        imageLeft + crop.left * imageWidth,
        imageTop + crop.top * imageHeight,
        crop.width * imageWidth,
        crop.height * imageHeight,
      );
      expect(mapped.left, closeTo(guide.left, .001));
      expect(mapped.top, closeTo(guide.top, .001));
      expect(mapped.right, closeTo(guide.right, .001));
      expect(mapped.bottom, closeTo(guide.bottom, .001));
      expect(crop.marginFraction, .03);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('selfie shutter does not request a document crop', (
    tester,
  ) async {
    var captures = 0;
    DocumentCaptureCrop? capturedCrop;
    await _pumpCapture(
      tester,
      kind: MediaKind.selfie,
      onCapture: (crop) async {
        captures++;
        capturedCrop = crop;
        return false;
      },
    );
    await tester.tap(find.byKey(const Key('camera-shutter')));
    await tester.pumpAndSettle();
    expect(captures, 1);
    expect(capturedCrop, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

Future<void> _pumpCapture(
  WidgetTester tester, {
  required MediaKind kind,
  required Future<bool> Function(DocumentCaptureCrop? crop) onCapture,
  double textScale = 1,
}) async {
  final repository = _PreviewCameraRepository();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: const EdgeInsets.only(top: 24, bottom: 20),
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: BlocProvider(
        create: (_) => CaptureCameraCubit(
          initializeCamera: InitializeCaptureCamera(repository),
          setFlash: SetCaptureCameraFlash(repository),
          closeCamera: CloseCaptureCamera(repository),
        ),
        child: InAppCameraPage(
          kind: kind,
          documentType: kind == MediaKind.document
              ? DocumentType.passport
              : null,
          previewBuilder: (_) => const ColoredBox(color: Color(0xFF62746A)),
          onCapture: onCapture,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _PreviewCameraRepository implements CaptureCameraRepository {
  @override
  Future<Result<CaptureCameraSession>> initialize(MediaKind kind) async =>
      Success(CaptureCameraSession(kind: kind, aspectRatio: 9 / 16));

  @override
  Future<Result<void>> close() async => const Success(null);

  @override
  Future<Result<CaptureCameraSession>> setFlash(bool enabled) async =>
      const Failure(
        AppFailure(code: 'UNSUPPORTED', message: 'Preview does not use flash.'),
      );
}
