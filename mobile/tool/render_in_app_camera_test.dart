// Render production camera controls with a synthetic camera background.
// Run from mobile/: flutter test --no-pub tool/render_in_app_camera_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/core/theme/app_theme.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';
import 'package:kyc_onboarding/features/kyc/domain/usecases/capture_camera_usecases.dart';
import 'package:kyc_onboarding/features/kyc/presentation/bloc/capture_camera_cubit.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/in_app_camera_page.dart';

import '../test/features/kyc/in_app_camera_page_test.dart'
    show FakeCaptureCameraRepository;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);

  const scenes = [
    ('document', MediaKind.document, Size(390, 844), 1.0),
    ('selfie', MediaKind.selfie, Size(390, 844), 1.0),
    ('document-small-large-text', MediaKind.document, Size(320, 568), 2.0),
    ('selfie-small-large-text', MediaKind.selfie, Size(320, 568), 2.0),
    ('document-landscape', MediaKind.document, Size(844, 390), 1.0),
    ('selfie-landscape', MediaKind.selfie, Size(844, 390), 1.0),
  ];
  for (final (name, kind, size, textScale) in scenes) {
    testWidgets('render production $name camera', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      final padding = FakeViewPadding(
        top: size.width < size.height ? 44 : 0,
        bottom: size.width < size.height ? 24 : 12,
      );
      tester.view.viewPadding = padding;
      tester.view.padding = padding;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetPadding);
      final repository = FakeCaptureCameraRepository()..canToggleFlash = true;
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light.copyWith(
              textTheme: AppTheme.light.textTheme.apply(fontFamily: 'Roboto'),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
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
                documentType: DocumentType.passport,
                previewBuilder: (_) => const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFB1B8AB),
                        Color(0xFF6D7E74),
                        Color(0xFF374F41),
                      ],
                    ),
                  ),
                ),
                onCapture: (_) async => true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final boundary =
          boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final rendered = await boundary.toImage(pixelRatio: 2);
        try {
          final bytes = await rendered.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (bytes == null) {
            throw StateError('PNG encoding returned no bytes.');
          }
          final file = File('../output/in-app-camera/$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          );
        } finally {
          rendered.dispose();
        }
      });
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _loadFonts() async {
  final fonts = Directory(
    '${_flutterRoot()}/bin/cache/artifacts/material_fonts',
  );
  final text = FontLoader('Roboto');
  for (final file in [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]) {
    text.addFont(_fontBytes('${fonts.path}/$file'));
  }
  await text.load();
  final icons = FontLoader('MaterialIcons');
  icons.addFont(_fontBytes('${fonts.path}/MaterialIcons-Regular.otf'));
  await icons.load();
}

Future<ByteData> _fontBytes(String path) async =>
    ByteData.sublistView(await File(path).readAsBytes());

String _flutterRoot() {
  final configured = Platform.environment['FLUTTER_ROOT'];
  if (configured != null && _hasFonts(configured)) return configured;
  var directory = File(Platform.resolvedExecutable).parent;
  while (directory.parent.path != directory.path) {
    if (_hasFonts(directory.path)) return directory.path;
    directory = directory.parent;
  }
  throw StateError('Set FLUTTER_ROOT to a Flutter SDK with material fonts.');
}

bool _hasFonts(String path) => File(
  '$path/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
).existsSync();
