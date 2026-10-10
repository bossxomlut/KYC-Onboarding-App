// Render the production Emerald Signature pages with synthetic profile data.
// Run from mobile/: flutter test --no-pub tool/render_signature_test.dart
// PNGs contain the app widgets and safe-area spacing, without OS status-bar chrome.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kyc_onboarding/core/theme/app_theme.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';
import 'package:kyc_onboarding/features/kyc/domain/usecases/kyc_usecases.dart';
import 'package:kyc_onboarding/features/kyc/presentation/bloc/kyc_cubit.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/capture_page.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/home_page.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/personal_details_page.dart';
import 'package:kyc_onboarding/features/kyc/presentation/widgets/kyc_scaffold.dart';

import '../test/features/kyc/kyc_cubit_test.dart' show FakeKycRepository;

const _profile = KycProfile(
  id: 'signature-preview',
  status: KycStatus.inProgress,
  nextStep: KycStep.document,
  personalDetails: PersonalDetails(
    fullName: 'Maya Nguyen',
    dateOfBirth: '1995-08-14',
    nationality: 'Vietnamese',
    address: '12 Example Street',
    documentNumber: 'DEMO123456',
  ),
);

const _screens = {
  'home': '/',
  'personal-details': '/kyc/details',
  'id-document': '/kyc/document',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);

  for (final screen in _screens.entries) {
    testWidgets('render production ${screen.key}', (tester) async {
      final previousShadows = debugDisableShadows;
      debugDisableShadows = false;
      try {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        const padding = FakeViewPadding(top: 44, bottom: 24);
        tester.view.viewPadding = padding;
        tester.view.padding = padding;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewPadding);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewInsets);

        final repository = FakeKycRepository()..profile = _profile;
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
          initialLocation: screen.value,
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) =>
                  HomePage(email: 'maya@kyc.example', onLogout: () async {}),
            ),
            GoRoute(
              path: '/kyc/details',
              builder: (_, _) => const PersonalDetailsPage(),
            ),
            GoRoute(
              path: '/kyc/document',
              builder: (_, _) => const CapturePage(kind: MediaKind.document),
            ),
          ],
        );
        addTearDown(() async {
          router.dispose();
          await cubit.close();
        });
        await cubit.load();

        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: BlocProvider.value(
              value: cubit,
              child: MaterialApp.router(
                debugShowCheckedModeBanner: false,
                theme: _renderTheme(),
                routerConfig: router,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        if (screen.key != 'home') {
          _expectBackArrow(tester, '${screen.key} before interactions');
        }
        if (screen.key == 'id-document') {
          await tester.tap(find.byKey(const Key('document-type')));
          await tester.pumpAndSettle();
          await tester.tap(find.text(DocumentType.nationalId.label).last);
          await tester.pumpAndSettle();
        }

        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.view.viewInsets.bottom, 0);
        expect(cubit.state.busy, isFalse);
        final boundary =
            boundaryKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        expect(boundary.size, const Size(390, 844));

        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 3);
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            if (bytes == null) {
              throw StateError('PNG encoding returned no bytes.');
            }
            final file = File(
              '../output/ui-revamp/emerald-signature/runtime/${screen.key}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(
              bytes.buffer.asUint8List(
                bytes.offsetInBytes,
                bytes.lengthInBytes,
              ),
            );
          } finally {
            image.dispose();
          }
        });
        expect(tester.takeException(), isNull);
        if (screen.key != 'home') {
          _expectBackArrow(tester, '${screen.key} after interactions');
        }
      } finally {
        debugDisableShadows = previousShadows;
      }
    });
  }
}

void _expectBackArrow(WidgetTester tester, String stage) {
  final context = tester.element(find.byType(KycScaffold));
  final route = ModalRoute.of(context);
  final appBar = tester.widget<AppBar>(find.byType(AppBar));
  expect(
    find.descendant(
      of: find.byType(AppBar),
      matching: find.byIcon(Icons.arrow_back),
    ),
    findsOneWidget,
    reason:
        '$stage: uri=${GoRouterState.of(context).uri}, '
        'canPop=${route?.canPop}, isCurrent=${route?.isCurrent}, '
        'leading=${appBar.leading.runtimeType}, '
        'automaticallyImplyLeading=${appBar.automaticallyImplyLeading}',
  );
}

ThemeData _renderTheme() {
  final theme = AppTheme.light;
  // The test engine uses Ahem for unspecified platform font fallbacks. Keep
  // production metrics and colors while supplying the SDK font we loaded.
  final filledStyle = theme.filledButtonTheme.style;
  return theme.copyWith(
    appBarTheme: theme.appBarTheme.copyWith(
      titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
        fontFamily: 'Roboto',
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: filledStyle?.copyWith(
        textStyle: WidgetStateProperty.resolveWith(
          (states) => filledStyle.textStyle
              ?.resolve(states)
              ?.copyWith(fontFamily: 'Roboto'),
        ),
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
