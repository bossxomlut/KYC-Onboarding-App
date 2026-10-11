// Render the production identity-checks panel with synthetic evidence.
// Run from mobile/: flutter test --no-pub tool/render_identity_checks_test.dart
// The PNG includes safe-area spacing without OS status-bar chrome.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/core/theme/app_theme.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';
import 'package:kyc_onboarding/features/kyc/presentation/widgets/verification_summary.dart';

const _recognizedText = 'MAYA NGUYEN\nDATE OF BIRTH 1995-08-14\nID DEMO123456';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);

  testWidgets('render completed production identity checks at 390px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    const padding = FakeViewPadding(top: 44, bottom: 24);
    tester.view.viewPadding = padding;
    tester.view.padding = padding;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetPadding);

    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _renderTheme(),
          home: Scaffold(
            appBar: AppBar(title: const Text('Review & submit')),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: VerificationSummary(
                  verification: KycVerification(
                    provider: 'aws',
                    status: VerificationStatus.completed,
                    documentId: 'synthetic-document',
                    selfieId: 'synthetic-selfie',
                    checkedAt: DateTime(2026, 10, 11, 10, 30),
                    ocr: const OcrVerification(
                      status: OcrStatus.succeeded,
                      text: _recognizedText,
                      fields: OcrFields(
                        fullName: 'Maya Nguyen',
                        dateOfBirth: '1995-08-14',
                        documentNumber: 'DEMO123456',
                      ),
                      confidence: 99.1,
                    ),
                    faceMatch: const FaceMatchVerification(
                      status: FaceMatchStatus.matched,
                      similarity: 97.4,
                      threshold: 90,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Maya Nguyen'), findsOneWidget);
    expect(find.text('Similarity score: 97.4 / 100'), findsOneWidget);
    expect(find.text(_recognizedText), findsNothing);
    expect(
      tester
          .getBottomLeft(
            find.textContaining('reviewer makes the final decision'),
          )
          .dy,
      lessThanOrEqualTo(820),
    );

    final boundary =
        boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    expect(boundary.size, const Size(390, 844));
    await tester.runAsync(() async {
      final rendered = await boundary.toImage(pixelRatio: 3);
      try {
        final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) throw StateError('PNG encoding returned no bytes.');
        final output = File(
          '../output/identity-verification/completed-checks.png',
        );
        await output.parent.create(recursive: true);
        await output.writeAsBytes(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
      } finally {
        rendered.dispose();
      }
    });
    expect(tester.takeException(), isNull);
  });
}

ThemeData _renderTheme() {
  final theme = AppTheme.light;
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
    appBarTheme: theme.appBarTheme.copyWith(
      titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
        fontFamily: 'Roboto',
      ),
    ),
  );
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
