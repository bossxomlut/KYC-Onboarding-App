import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kyc_onboarding/app/di/dependencies.dart';
import 'package:kyc_onboarding/app/kyc_app.dart';
import 'package:kyc_onboarding/core/security/token_store.dart';
import 'package:kyc_onboarding/features/kyc/data/datasources/camera_datasource.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';
import 'demo_fixtures.dart';

/// Only the camera boundary is replaced. HTTP, auth, SQL and media processing
/// remain production implementations and use the running real API.
class SyntheticCamera implements CameraDataSource {
  @override
  Future<CapturedMedia?> capture(
    MediaKind kind,
    String profileId, {
    DocumentType? documentType,
  }) async {
    final bytes = kind == MediaKind.document ? documentFixture : selfieFixture;
    final file = File(
      '${(await getTemporaryDirectory()).path}/demo_${kind.name}.jpg',
    );
    await file.writeAsBytes(bytes, flush: true);
    return CapturedMedia(
      kind: kind,
      filePath: file.path,
      bytes: bytes,
      documentType: documentType,
    );
  }

  @override
  Future<CapturedMedia?> recover(MediaKind kind, String profileId) async =>
      null;
  @override
  Future<void> remove(CapturedMedia media) async {
    final file = File(media.filePath);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> discard(String profileId) async {}
}

class FailFirstDocumentUpload extends Interceptor {
  bool failed = false;
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!failed &&
        options.path == '/kyc/media/document' &&
        options.method == 'POST') {
      failed = true;
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ),
      );
    } else {
      handler.next(options);
    }
  }
}

Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  int seconds = 30,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsWidgets);
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> field(WidgetTester tester, String label, String value) async {
  final finder = find.widgetWithText(TextFormField, label);
  await tester.ensureVisible(finder);
  await tester.enterText(finder, value);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

Future<void> pause(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const apiUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:3000/api/v1',
  );
  const mailUrl = String.fromEnvironment(
    'MAILPIT_URL',
    defaultValue: 'http://127.0.0.1:8025',
  );
  const email = String.fromEnvironment(
    'DEMO_EMAIL',
    defaultValue: 'recording@kyc.example',
  );
  testWidgets(
    'real API registration, saved resume, failed upload retry, rejection and verification',
    (tester) async {
      final tokens = SecureTokenStore(
        const FlutterSecureStorage(
          iOptions: IOSOptions(
            accessibility: KeychainAccessibility.unlocked_this_device,
          ),
        ),
      );
      await tokens.clear();
      var di = configureDependencies(
        baseUrl: apiUrl,
        tokens: tokens,
        camera: SyntheticCamera(),
      );
      await tester.pumpWidget(KycApp(dependencies: di));
      await waitFor(tester, find.text('Welcome back'));
      await pause(tester);
      await tap(tester, find.text('New here? Create an account'));
      await field(tester, 'Email', email);
      await field(tester, 'Password', 'DemoOnlyPass123!');
      await field(tester, 'Confirm password', 'DemoOnlyPass123!');
      await tap(tester, find.text('Create account'));
      await waitFor(tester, find.text('Verify your email'));
      final mail = Dio(BaseOptions(baseUrl: mailUrl));
      String? code;
      for (var attempt = 0; attempt < 30 && code == null; attempt++) {
        final list = (await mail.get<Map<String, dynamic>>(
          '/api/v1/messages',
        )).data!;
        for (final summary in list['messages'] as List) {
          if (!(summary['To'] as List).any(
            (recipient) => recipient['Address'] == email,
          )) {
            continue;
          }
          final detail = (await mail.get<Map<String, dynamic>>(
            '/api/v1/message/${summary['ID']}',
          )).data!;
          code = RegExp(
            r'verification code is (\d{6})',
          ).firstMatch(detail['Text'] as String)?.group(1);
          if (code != null) break;
        }
        if (code == null) await tester.pump(const Duration(seconds: 1));
      }
      expect(
        code,
        isNotNull,
        reason: 'Read OTP from the local Mailpit catcher.',
      );
      await field(tester, 'Verification code', code!);
      await tap(tester, find.text('Verify email'));
      await waitFor(tester, find.byKey(const Key('kyc-next')));
      await pause(tester);
      await tap(tester, find.byKey(const Key('kyc-next')));
      for (final entry in {
        'fullName': 'Maya Demo',
        'dateOfBirth': '1995-06-15',
        'nationality': 'Vietnamese',
        'address': '123 Demo Street, Demo City',
        'documentNumber': 'DEMO000123',
      }.entries) {
        await tester.ensureVisible(find.byKey(Key(entry.key)));
        await tester.enterText(find.byKey(Key(entry.key)), entry.value);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
      }
      await tap(tester, find.byKey(const Key('save-details')));
      await waitFor(tester, find.byKey(const Key('capture-document')));
      // Recreate the whole app/container. The secure refresh credential and
      // server-saved draft must restore to the document step without data loss.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await di.reset();
      di = configureDependencies(
        baseUrl: apiUrl,
        tokens: tokens,
        camera: SyntheticCamera(),
      );
      di<Dio>().interceptors.add(FailFirstDocumentUpload());
      await tester.pumpWidget(KycApp(dependencies: di));
      await waitFor(tester, find.byKey(const Key('kyc-next')));
      expect(find.text('In progress'), findsOneWidget);
      await pause(tester);
      await tap(tester, find.byKey(const Key('kyc-next')));
      await waitFor(tester, find.byKey(const Key('capture-document')));
      await tap(tester, find.byKey(const Key('capture-document')));
      await waitFor(tester, find.byKey(const Key('retry-upload')));
      await pause(tester);
      await tap(tester, find.byKey(const Key('retry-upload')));
      await waitFor(tester, find.byKey(const Key('capture-selfie')));
      await pause(tester);
      await tap(tester, find.byKey(const Key('capture-selfie')));
      await waitFor(tester, find.byKey(const Key('submit-kyc')));
      expect(find.text('Maya Demo'), findsOneWidget);
      await pause(tester);
      await tap(tester, find.byKey(const Key('submit-kyc')));
      await waitFor(tester, find.text('Pending review'));
      for (
        var attempt = 0;
        attempt < 30 &&
            find.byKey(const Key('resubmit-kyc')).evaluate().isEmpty;
        attempt++
      ) {
        await tester.pump(const Duration(seconds: 1));
        await tap(tester, find.byKey(const Key('refresh-status')));
      }
      await waitFor(tester, find.byKey(const Key('resubmit-kyc')));
      expect(
        find.text('Please retake your demo selfie in better light.'),
        findsOneWidget,
      );
      await pause(tester);
      await tap(tester, find.byKey(const Key('resubmit-kyc')));
      await waitFor(tester, find.byKey(const Key('capture-selfie')));
      await tap(tester, find.byKey(const Key('capture-selfie')));
      await waitFor(tester, find.byKey(const Key('submit-kyc')));
      expect(find.text('Maya Demo'), findsOneWidget);
      await tap(tester, find.byKey(const Key('submit-kyc')));
      await waitFor(tester, find.text('Pending review'));
      for (
        var attempt = 0;
        attempt < 30 && find.text('Verified').evaluate().isEmpty;
        attempt++
      ) {
        await tester.pump(const Duration(seconds: 1));
        await tap(tester, find.byKey(const Key('refresh-status')));
      }
      await waitFor(tester, find.text('Verified'));
      await pause(tester);
      await tap(tester, find.text('Back to home'));
      await tap(tester, find.byKey(const Key('logout')));
      await waitFor(tester, find.text('Welcome back'));
      mail.close();
      await tester.pumpWidget(const SizedBox());
      await di.reset();
    },
  );
}
