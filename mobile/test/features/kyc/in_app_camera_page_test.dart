import 'dart:async';

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
  for (final kind in MediaKind.values) {
    testWidgets('${kind.name} shows the correct lens and framing guide', (
      tester,
    ) async {
      final repository = FakeCaptureCameraRepository();
      await pumpCamera(tester, repository, kind: kind);

      expect(repository.initializedKinds, [kind]);
      expect(
        find.text(kind == MediaKind.document ? 'Rear camera' : 'Front camera'),
        findsOneWidget,
      );
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
      expect(find.byKey(const Key('camera-preview')), findsOneWidget);
      expect(find.byTooltip('Switch camera'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('initialization gates shutter until the camera is ready', (
    tester,
  ) async {
    final repository = FakeCaptureCameraRepository()
      ..initializeGate = Completer<void>();
    await pumpCamera(tester, repository, settle: false);

    expect(find.text('Starting camera…'), findsOneWidget);
    expect(shutter(tester).onPressed, isNull);
    repository.initializeGate!.complete();
    await tester.pumpAndSettle();
    expect(shutter(tester).onPressed, isNotNull);
  });

  testWidgets('camera failure shows a useful error and supports retry', (
    tester,
  ) async {
    final repository = FakeCaptureCameraRepository()..failInitialize = true;
    await pumpCamera(tester, repository);

    expect(find.text('Camera unavailable'), findsOneWidget);
    expect(
      find.text('Allow camera access in your device settings.'),
      findsOneWidget,
    );
    expect(shutter(tester).onPressed, isNull);
    repository.failInitialize = false;
    await tester.tap(find.byKey(const Key('camera-retry')));
    await tester.pumpAndSettle();
    expect(repository.initializedKinds.length, 2);
    expect(shutter(tester).onPressed, isNotNull);
    expect(find.byKey(const Key('camera-preview')), findsOneWidget);
  });

  testWidgets('document flash toggle is hidden for selfie', (tester) async {
    final repository = FakeCaptureCameraRepository()..canToggleFlash = true;
    await pumpCamera(tester, repository);
    expect(find.byTooltip('Turn flash on'), findsOneWidget);
    await tester.tap(find.byTooltip('Turn flash on'));
    await tester.pumpAndSettle();
    expect(repository.flashEnabled, isTrue);
    expect(find.byTooltip('Turn flash off'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await pumpCamera(tester, repository, kind: MediaKind.selfie);
    expect(find.byTooltip('Turn flash on'), findsNothing);
    expect(find.byTooltip('Turn flash off'), findsNothing);
  });

  testWidgets('flash failure keeps the preview and shutter available', (
    tester,
  ) async {
    final repository = FakeCaptureCameraRepository()
      ..canToggleFlash = true
      ..failFlash = true;
    await pumpCamera(tester, repository);
    await tester.tap(find.byTooltip('Turn flash on'));
    await tester.pumpAndSettle();
    expect(find.text('Flash is unavailable on this camera.'), findsOneWidget);
    expect(find.byKey(const Key('camera-preview')), findsOneWidget);
    expect(shutter(tester).onPressed, isNotNull);
  });

  testWidgets(
    'successful shutter returns once and blocks dismissal while saving',
    (tester) async {
      final repository = FakeCaptureCameraRepository();
      final captureGate = Completer<bool>();
      var captures = 0;
      bool? result;
      await pumpCamera(
        tester,
        repository,
        onCapture: (_) {
          captures++;
          return captureGate.future;
        },
        onResult: (value) => result = value,
      );
      await tester.tap(find.byKey(const Key('camera-shutter')));
      await tester.pump();
      expect(captures, 1);
      expect(shutter(tester).onPressed, isNull);
      await tester.tap(find.byKey(const Key('camera-shutter')));
      await tester.tap(find.byTooltip('Close camera'));
      await tester.pump();
      expect(captures, 1);
      expect(find.byType(InAppCameraPage), findsOneWidget);

      captureGate.complete(true);
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(repository.closeCalls, 1);
      expect(find.text('Photo destination'), findsOneWidget);
    },
  );

  testWidgets('failed shutter stays open for another attempt', (tester) async {
    await pumpCamera(
      tester,
      FakeCaptureCameraRepository(),
      onCapture: (_) async => false,
    );
    await tester.tap(find.byKey(const Key('camera-shutter')));
    await tester.pumpAndSettle();
    expect(find.byType(InAppCameraPage), findsOneWidget);
    expect(
      find.text('Photo could not be saved. Please try again.'),
      findsOneWidget,
    );
    expect(shutter(tester).onPressed, isNotNull);
  });

  testWidgets('unexpected capture failure stays open without an async error', (
    tester,
  ) async {
    await pumpCamera(
      tester,
      FakeCaptureCameraRepository(),
      onCapture: (_) async => throw StateError('Unexpected camera failure'),
    );
    await tester.tap(find.byKey(const Key('camera-shutter')));
    await tester.pumpAndSettle();
    expect(find.byType(InAppCameraPage), findsOneWidget);
    expect(
      find.text('Photo could not be saved. Please try again.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing camera returns without taking a photo', (tester) async {
    var captures = 0;
    bool? result;
    final repository = FakeCaptureCameraRepository();
    await pumpCamera(
      tester,
      repository,
      onCapture: (_) async {
        captures++;
        return true;
      },
      onResult: (value) => result = value,
    );
    await tester.tap(find.byTooltip('Close camera'));
    await tester.pumpAndSettle();
    expect(captures, 0);
    expect(result, isFalse);
    expect(repository.closeCalls, 1);
    expect(find.text('Photo destination'), findsOneWidget);
  });

  testWidgets('system Back closes the camera before returning', (tester) async {
    final repository = FakeCaptureCameraRepository();
    bool? result;
    await pumpCamera(tester, repository, onResult: (value) => result = value);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(repository.closeCalls, 1);
    expect(find.text('Photo destination'), findsOneWidget);
  });

  for (final kind in MediaKind.values) {
    testWidgets('${kind.name} fits a small display with large text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpCamera(
        tester,
        FakeCaptureCameraRepository(),
        kind: kind,
        textScaler: TextScaler.linear(2),
      );
      expect(find.byKey(const Key('camera-shutter')), findsOneWidget);
      expect(tester.takeException(), isNull);
      final guide = tester.getSize(
        find.byKey(
          Key(
            kind == MediaKind.document
                ? 'document-camera-guide'
                : 'selfie-camera-guide',
          ),
        ),
      );
      expect(guide.width, greaterThan(40));
      expect(guide.height, greaterThan(40));
    });
  }
}

IconButton shutter(WidgetTester tester) =>
    tester.widget<IconButton>(find.byKey(const Key('camera-shutter')));

Future<void> pumpCamera(
  WidgetTester tester,
  FakeCaptureCameraRepository repository, {
  MediaKind kind = MediaKind.document,
  Future<bool> Function(DocumentCaptureCrop? crop)? onCapture,
  ValueChanged<bool?>? onResult,
  bool settle = true,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      navigatorKey: navigator,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: const Scaffold(body: Text('Photo destination')),
    ),
  );
  final result = navigator.currentState!.push<bool>(
    MaterialPageRoute(
      builder: (_) => BlocProvider(
        create: (_) => CaptureCameraCubit(
          initializeCamera: InitializeCaptureCamera(repository),
          setFlash: SetCaptureCameraFlash(repository),
          closeCamera: CloseCaptureCamera(repository),
        ),
        child: InAppCameraPage(
          kind: kind,
          documentType: DocumentType.passport,
          previewBuilder: (_) => const ColoredBox(
            key: Key('camera-preview'),
            color: Color(0xFF62746A),
          ),
          onCapture: onCapture ?? (_) async => true,
        ),
      ),
    ),
  );
  unawaited(result.then(onResult ?? (_) {}));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
}

class FakeCaptureCameraRepository implements CaptureCameraRepository {
  final initializedKinds = <MediaKind>[];
  Completer<void>? initializeGate;
  bool failInitialize = false;
  bool canToggleFlash = false;
  bool flashEnabled = false;
  bool failFlash = false;
  int closeCalls = 0;
  MediaKind _kind = MediaKind.document;

  CaptureCameraSession get session => CaptureCameraSession(
    kind: _kind,
    aspectRatio: 3 / 4,
    canToggleFlash: canToggleFlash,
    flashEnabled: flashEnabled,
  );

  @override
  Future<Result<CaptureCameraSession>> initialize(MediaKind kind) async {
    initializedKinds.add(kind);
    _kind = kind;
    if (initializeGate != null) await initializeGate!.future;
    if (failInitialize) {
      return const Failure(
        AppFailure(
          code: 'CAMERA_PERMISSION',
          message: 'Allow camera access in your device settings.',
        ),
      );
    }
    return Success(session);
  }

  @override
  Future<Result<CaptureCameraSession>> setFlash(bool enabled) async {
    if (failFlash) {
      return const Failure(
        AppFailure(
          code: 'CAMERA_FLASH_UNAVAILABLE',
          message: 'Flash is unavailable on this camera.',
        ),
      );
    }
    flashEnabled = enabled;
    return Success(session);
  }

  @override
  Future<Result<void>> close() async {
    closeCalls++;
    return const Success(null);
  }
}
