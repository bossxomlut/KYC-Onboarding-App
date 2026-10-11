import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kyc_onboarding/app/di/dependencies.dart';
import 'package:kyc_onboarding/app/kyc_app.dart';
import 'package:kyc_onboarding/core/security/token_store.dart';
import 'package:kyc_onboarding/features/kyc/data/datasources/camera_datasource.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/camera_capture_crop.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';
import 'package:path_provider/path_provider.dart';

import 'demo_fixtures.dart';

/// Recording-only camera boundary. Every screen, API call and review decision
/// uses the running app. The illustrations come exclusively from demo/assets.
class RecordingSyntheticCamera implements CameraDataSource {
  @override
  Future<CapturedMedia?> capture(
    MediaKind kind,
    String profileId, {
    DocumentType? documentType,
    CameraCaptureCrop? crop,
  }) async {
    final bytes = kind == MediaKind.document ? documentFixture : selfieFixture;
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/demo_recording_${kind.name}.jpg');
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

Future<void> recordingPause(
  WidgetTester tester, {
  Duration duration = const Duration(seconds: 2),
}) async {
  // A wall-clock pause keeps milestones visible in a simctl screen recording.
  await tester.runAsync(() => Future<void>.delayed(duration));
  await tester.pump();
}

Future<void> recordingStep(
  WidgetTester tester,
  String slug,
  String label,
) async {
  debugPrint('DEMO_STEP|$slug|$label');
  await recordingPause(tester);
}

Future<void> recordingWaitFor(
  WidgetTester tester,
  Finder finder, {
  int seconds = 45,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsWidgets);
  await tester.pumpAndSettle();
}

Future<void> recordingWaitEnabled(WidgetTester tester, Key key) =>
    recordingWaitFor(
      tester,
      find.byWidgetPredicate(
        (widget) =>
            widget.key == key &&
            ((widget is ButtonStyleButton && widget.onPressed != null) ||
                (widget is IconButton && widget.onPressed != null)),
      ),
    );

Future<void> recordingTap(WidgetTester tester, Finder finder) async {
  await recordingWaitFor(tester, finder);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await recordingPause(
    tester,
    duration: const Duration(milliseconds: 350),
  );
  await tester.tap(finder);
  await tester.pumpAndSettle();
  await recordingPause(
    tester,
    duration: const Duration(milliseconds: 350),
  );
}

Future<void> recordingEnter(
  WidgetTester tester,
  Finder finder,
  String value,
) async {
  await recordingWaitFor(tester, finder);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.enterText(finder, value);
  await recordingPause(
    tester,
    duration: const Duration(milliseconds: 650),
  );
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

Future<void> recordingLogin(
  WidgetTester tester,
  String email,
  String password, {
  required String role,
  required String switchSlug,
}) async {
  await recordingWaitFor(tester, find.text('Welcome back'));
  await recordingEnter(
    tester,
    find.widgetWithText(TextFormField, 'Email'),
    email,
  );
  await recordingEnter(
    tester,
    find.widgetWithText(TextFormField, 'Password'),
    password,
  );
  final accountLabel = role == 'User' ? 'Applicant (User)' : role;
  expect(
    tester
        .widget<TextFormField>(find.widgetWithText(TextFormField, 'Email'))
        .controller!
        .text,
    email,
  );
  await recordingStep(
    tester,
    switchSlug,
    'Sign in as $accountLabel: $email',
  );
  await recordingTap(tester, find.text('Sign in'));
  await recordingWaitEnabled(tester, const Key('logout'));
  await recordingWaitEnabled(tester, const Key('account-access'));
  await recordingTap(tester, find.byKey(const Key('account-access')));
  await recordingWaitFor(tester, find.text(email));
  await recordingWaitFor(tester, find.byKey(const Key('current-role')));
  expect(find.text(email), findsOneWidget);
  expect(
    tester.widget<Text>(find.byKey(const Key('current-role'))).data,
    'Current role: $role',
  );
  await recordingStep(
    tester,
    '$switchSlug-identity',
    'Current account is $accountLabel: $email',
  );
  await recordingTap(tester, find.byTooltip('Back'));
  await recordingWaitEnabled(tester, const Key('logout'));
}

Future<void> recordingLogout(WidgetTester tester) async {
  await recordingWaitEnabled(tester, const Key('logout'));
  await recordingTap(tester, find.byKey(const Key('logout')));
  await recordingWaitFor(tester, find.text('Welcome back'));
}

Future<void> recordingPhoto(
  WidgetTester tester,
  String semanticLabel,
  String slug,
  String label,
) async {
  final photo = find.byWidgetPredicate(
    (widget) => widget is Image && widget.semanticLabel == semanticLabel,
  );
  await recordingWaitFor(tester, photo);
  await tester.ensureVisible(photo);
  await tester.pumpAndSettle();
  await recordingStep(tester, slug, label);
}

Future<void> recordingContinueCapture(
  WidgetTester tester,
  MediaKind kind,
  Finder nextScreen,
) async {
  await recordingWaitEnabled(tester, Key('continue-${kind.name}'));
  await recordingTap(tester, find.byKey(Key('continue-${kind.name}')));
  await recordingWaitFor(tester, nextScreen);
}

Future<String> recordingOtp(WidgetTester tester, Dio mail, String email) async {
  for (var attempt = 0; attempt < 45; attempt++) {
    final list =
        (await mail.get<Map<String, dynamic>>('/api/v1/messages')).data!;
    for (final summary in list['messages'] as List) {
      if (!(summary['To'] as List).any(
        (recipient) => recipient['Address'] == email,
      )) {
        continue;
      }
      final detail = (await mail.get<Map<String, dynamic>>(
        '/api/v1/message/${summary['ID']}',
      ))
          .data!;
      final code = RegExp(
        r'verification code is (\d{6})',
      ).firstMatch(detail['Text'] as String)?.group(1);
      if (code != null) return code;
    }
    await recordingPause(tester, duration: const Duration(seconds: 1));
  }
  throw StateError('No OTP was delivered to the local Mailpit demo catcher.');
}

Future<void> recordingOpenReview(
  WidgetTester tester,
  String email,
  String fullName,
) async {
  await recordingWaitEnabled(tester, const Key('review-profiles'));
  await recordingTap(tester, find.byKey(const Key('review-profiles')));
  await recordingWaitFor(tester, find.byKey(const Key('review-search')));
  await recordingEnter(
    tester,
    find.byKey(const Key('review-search')),
    email,
  );
  final applicant = find.widgetWithText(ListTile, email);
  await recordingWaitFor(tester, applicant);
  await tester.ensureVisible(applicant);
  await tester.pumpAndSettle();
  await recordingStep(
    tester,
    'review-queue',
    'Separate reviewer account selects applicant profile: $email',
  );
  await recordingTap(tester, applicant);
  await recordingWaitEnabled(tester, const Key('review-approve'));
  await recordingWaitFor(tester, find.text(fullName));
  await recordingStep(
      tester, 'review-details', 'Reviewer checks personal details');
  await recordingPhoto(
    tester,
    'Submitted identity document',
    'review-document',
    'Reviewer checks the synthetic identity document',
  );
  await recordingPhoto(
    tester,
    'Submitted selfie',
    'review-selfie',
    'Reviewer checks the synthetic selfie',
  );
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
  const password = String.fromEnvironment(
    'DEMO_PASSWORD',
    defaultValue: 'DemoOnlyPass123!',
  );
  const reviewerEmail = String.fromEnvironment('DEMO_REVIEWER_EMAIL');
  const reviewerPassword = String.fromEnvironment('DEMO_REVIEWER_PASSWORD');
  const fullName = String.fromEnvironment(
    'DEMO_FULL_NAME',
    defaultValue: 'Maya Demo',
  );
  const dateOfBirth = String.fromEnvironment(
    'DEMO_DATE_OF_BIRTH',
    defaultValue: '1995-06-15',
  );
  const nationality = String.fromEnvironment(
    'DEMO_NATIONALITY',
    defaultValue: 'Vietnamese',
  );
  const address = String.fromEnvironment(
    'DEMO_ADDRESS',
    defaultValue: '123 Demo Street, Demo City',
  );
  const documentNumber = String.fromEnvironment(
    'DEMO_DOCUMENT_NUMBER',
    defaultValue: 'DEMO000123',
  );
  const rejectionReason = 'Please retake your demo selfie in better light.';

  testWidgets(
    'record synthetic applicant and reviewer main flow with the real API',
    (tester) async {
      if (!email.endsWith('@kyc.example') ||
          !reviewerEmail.endsWith('@kyc.example') ||
          email.trim().toLowerCase() == reviewerEmail.trim().toLowerCase() ||
          password.isEmpty ||
          reviewerPassword.isEmpty) {
        throw StateError(
          'Use distinct synthetic @kyc.example applicant and reviewer accounts. '
          'Provide DEMO_REVIEWER_EMAIL and DEMO_REVIEWER_PASSWORD for a verified '
          'local reviewer; no account or permission is provisioned by this test.',
        );
      }
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
        camera: RecordingSyntheticCamera(),
      );
      final mail = Dio(BaseOptions(baseUrl: mailUrl));
      try {
        await tester.pumpWidget(KycApp(dependencies: di));
        await recordingWaitFor(tester, find.text('Welcome back'));
        debugPrint('DEMO_READY');
        await recordingPause(tester, duration: const Duration(seconds: 4));
        await recordingStep(
            tester, 'welcome', 'Identity onboarding starts here');

        await recordingTap(tester, find.text('New here? Create an account'));
        await recordingEnter(
          tester,
          find.widgetWithText(TextFormField, 'Email'),
          email,
        );
        await recordingEnter(
          tester,
          find.widgetWithText(TextFormField, 'Password'),
          password,
        );
        await recordingEnter(
          tester,
          find.widgetWithText(TextFormField, 'Confirm password'),
          password,
        );
        await recordingStep(
            tester, 'registration', 'Create a synthetic account');
        await recordingTap(tester, find.text('Create account'));
        await recordingWaitFor(tester, find.text('Verify your email'));
        await recordingStep(
            tester, 'email-otp', 'Verify email with a local OTP');
        final code = await recordingOtp(tester, mail, email);
        await recordingEnter(tester, find.byKey(const Key('otp-input')), code);
        await recordingTap(tester, find.text('Verify email'));
        await recordingWaitEnabled(tester, const Key('kyc-next'));
        await recordingStep(
            tester, 'registered', 'Email verified; profile is ready');

        await recordingLogout(tester);
        await recordingLogin(
          tester,
          email,
          password,
          role: 'User',
          switchSlug: 'applicant-sign-in',
        );
        await recordingStep(
            tester, 'applicant-login', 'Sign in to the demo account');
        await recordingTap(tester, find.byKey(const Key('kyc-next')));
        await recordingWaitFor(tester, find.byKey(const Key('fullName')));
        for (final entry in {
          'fullName': fullName,
          'nationality': nationality,
          'address': address.split(',').first,
          'documentNumber': documentNumber,
        }.entries) {
          await recordingEnter(tester, find.byKey(Key(entry.key)), entry.value);
        }
        await recordingTap(tester, find.byKey(const Key('dateOfBirth')));
        tester
            .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
            .onDateTimeChanged(DateTime.parse(dateOfBirth));
        await tester.pumpAndSettle();
        await recordingPause(tester);
        await recordingTap(
            tester, find.byKey(const Key('confirm-date-of-birth')));
        await recordingStep(
            tester, 'personal-details', 'Enter fictional personal details');
        await recordingTap(tester, find.byKey(const Key('save-details')));
        await recordingWaitFor(
            tester, find.byKey(const Key('capture-document')));
        await recordingStep(
            tester, 'saved-progress', 'Personal details are saved');

        // Recreate the complete app/container while retaining the real secure
        // refresh credential; the server restores the saved document step.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await di.reset();
        di = configureDependencies(
          baseUrl: apiUrl,
          tokens: tokens,
          camera: RecordingSyntheticCamera(),
        );
        await tester.pumpWidget(KycApp(dependencies: di));
        await recordingWaitEnabled(tester, const Key('kyc-next'));
        expect(find.text('In progress'), findsOneWidget);
        await recordingStep(tester, 'session-restored',
            'Session and saved progress are restored');
        await recordingTap(tester, find.byKey(const Key('kyc-next')));
        await recordingWaitFor(
            tester, find.byKey(const Key('capture-document')));
        await recordingStep(
            tester, 'document-step', 'Continue at the identity document step');
        await recordingTap(tester, find.byKey(const Key('capture-document')));
        await recordingWaitEnabled(tester, const Key('continue-document'));
        await recordingPhoto(
          tester,
          'Document photo',
          'document-uploaded',
          'Synthetic document uploaded privately',
        );
        await recordingContinueCapture(
          tester,
          MediaKind.document,
          find.byKey(const Key('capture-selfie')),
        );
        await recordingStep(
            tester, 'selfie-step', 'Continue with a synthetic selfie');
        await recordingTap(tester, find.byKey(const Key('capture-selfie')));
        await recordingWaitEnabled(tester, const Key('continue-selfie'));
        await recordingPhoto(
          tester,
          'Selfie photo',
          'selfie-uploaded',
          'Synthetic selfie uploaded privately',
        );
        await recordingContinueCapture(
          tester,
          MediaKind.selfie,
          find.byKey(const Key('submit-kyc')),
        );
        await recordingWaitFor(tester, find.text(fullName));
        await recordingStep(
            tester, 'review-profile', 'Review details before submitting');

        await recordingTap(tester, find.text('Edit').first);
        await recordingWaitFor(tester, find.byKey(const Key('address')));
        await recordingEnter(
          tester,
          find.byKey(const Key('address')),
          address,
        );
        await recordingStep(
            tester, 'edit-details', 'Edit the address from Review');
        await recordingTap(tester, find.byKey(const Key('save-details')));
        await recordingWaitFor(tester, find.byKey(const Key('submit-kyc')));
        expect(find.text(address), findsOneWidget);
        await recordingPhoto(
          tester,
          'Your private document photo',
          'review-private-document',
          'Check the private document preview',
        );
        await recordingPhoto(
          tester,
          'Your private selfie photo',
          'review-private-selfie',
          'Check the private selfie preview',
        );
        await recordingTap(tester, find.text('Edit').last);
        await recordingWaitFor(tester, find.byKey(const Key('capture-selfie')));
        await recordingStep(tester, 'retake-before-submit',
            'Retake the synthetic selfie before submission');
        await recordingTap(tester, find.byKey(const Key('capture-selfie')));
        await recordingWaitEnabled(tester, const Key('continue-selfie'));
        await recordingPause(tester);
        await recordingContinueCapture(
          tester,
          MediaKind.selfie,
          find.byKey(const Key('submit-kyc')),
        );
        await recordingWaitEnabled(tester, const Key('submit-kyc'));
        await recordingTap(tester, find.byKey(const Key('submit-kyc')));
        await recordingWaitFor(tester, find.text('Pending review'));
        await recordingStep(
            tester, 'pending-review', 'First submission is pending review');
        await recordingTap(tester, find.text('Back to home'));
        await recordingLogout(tester);

        await recordingLogin(
          tester,
          reviewerEmail,
          reviewerPassword,
          role: 'Reviewer',
          switchSlug: 'reviewer-sign-in',
        );
        await recordingStep(
            tester, 'reviewer-login', 'Sign in as the synthetic reviewer');
        await recordingOpenReview(tester, email, fullName);
        await recordingTap(tester, find.byKey(const Key('review-reject')));
        await recordingEnter(
          tester,
          find.byKey(const Key('rejection-reason')),
          rejectionReason,
        );
        await recordingTap(
            tester, find.widgetWithText(CheckboxListTile, 'Selfie'));
        await recordingStep(tester, 'request-selfie-update',
            'Request a selfie update with a reason');
        await recordingTap(tester, find.text('Save rejection'));
        await recordingWaitFor(tester, find.byKey(const Key('review-search')));
        await recordingStep(tester, 'review-rejected',
            'Reviewer saves the rejection through the app');
        await recordingTap(tester, find.byTooltip('Back'));
        await recordingLogout(tester);

        await recordingLogin(
          tester,
          email,
          password,
          role: 'User',
          switchSlug: 'applicant-return-sign-in',
        );
        await recordingWaitFor(tester, find.text(rejectionReason));
        await tester.ensureVisible(find.text(rejectionReason));
        await tester.pumpAndSettle();
        await recordingStep(tester, 'applicant-rejected',
            'Applicant sees the selfie correction request');
        await recordingTap(tester, find.byKey(const Key('kyc-next-step')));
        await recordingWaitFor(tester, find.byKey(const Key('capture-selfie')));
        await recordingStep(tester, 'selfie-only-resume',
            'Accepted details and document remain saved');
        await recordingTap(tester, find.byKey(const Key('capture-selfie')));
        await recordingWaitEnabled(tester, const Key('continue-selfie'));
        await recordingPhoto(
          tester,
          'Selfie photo',
          'replacement-selfie',
          'Replace only the requested synthetic selfie',
        );
        await recordingContinueCapture(
          tester,
          MediaKind.selfie,
          find.byKey(const Key('submit-kyc')),
        );
        expect(find.text(fullName), findsOneWidget);
        expect(find.text(address), findsOneWidget);
        await recordingStep(tester, 'resubmission-review',
            'Review the preserved details and replacement selfie');
        await recordingTap(tester, find.byKey(const Key('submit-kyc')));
        await recordingWaitFor(tester, find.text('Pending review'));
        await recordingStep(
            tester, 'resubmitted', 'Second submission is pending review');
        await recordingTap(tester, find.text('Back to home'));
        await recordingLogout(tester);

        await recordingLogin(
          tester,
          reviewerEmail,
          reviewerPassword,
          role: 'Reviewer',
          switchSlug: 'reviewer-return-sign-in',
        );
        await recordingOpenReview(tester, email, fullName);
        await recordingTap(tester, find.byKey(const Key('review-approve')));
        await recordingWaitFor(tester, find.text('Approve this identity?'));
        await recordingStep(tester, 'approve-confirmation',
            'Confirm the checked identity submission');
        await recordingTap(tester, find.text('Approve'));
        await recordingWaitFor(tester, find.byKey(const Key('review-search')));
        await recordingStep(
            tester, 'review-approved', 'Reviewer approves through the app');
        await recordingTap(tester, find.byTooltip('Back'));
        await recordingLogout(tester);

        await recordingLogin(
          tester,
          email,
          password,
          role: 'User',
          switchSlug: 'applicant-final-sign-in',
        );
        await recordingTap(tester, find.byKey(const Key('kyc-next')));
        await recordingWaitFor(tester, find.text('Verified'));
        await recordingTap(tester, find.byKey(const Key('refresh-status')));
        await recordingWaitFor(tester, find.text('Verified'));
        await recordingStep(
            tester, 'verified', 'Identity verified; applicant sees the result');
        await recordingTap(tester, find.byKey(const Key('view-kyc-history')));
        await recordingWaitFor(tester, find.text('Submission #1'));
        expect(find.text('Submission #2'), findsOneWidget);
        await recordingStep(tester, 'submission-history',
            'Both submission rounds stay in history');
        final original = find.ancestor(
          of: find.text('Submission #1'),
          matching: find.byType(InkWell),
        );
        await recordingTap(tester, original);
        await recordingWaitFor(tester, find.text(rejectionReason));
        await recordingStep(tester, 'original-submission',
            'Original rejected submission remains read only');
        await recordingPhoto(
          tester,
          'Your private document photo',
          'history-private-document',
          'Original synthetic document remains private and readable',
        );
        await recordingPhoto(
          tester,
          'Your private selfie photo',
          'history-private-selfie',
          'Original synthetic selfie remains in submission history',
        );
        expect(find.text('Edit'), findsNothing);
        await recordingTap(
            tester, find.byKey(const Key('history-detail-close')));
        await recordingTap(tester, find.byTooltip('Back'));
        await recordingTap(tester, find.text('Back to home'));
        await recordingLogout(tester);
        await recordingStep(
            tester, 'logout', 'Signed out safely at the end of the flow');
        await recordingPause(tester, duration: const Duration(seconds: 4));
        debugPrint('DEMO_FINISHED');
        // Let the external recorder stop before the test removes the app tree.
        await recordingPause(tester, duration: const Duration(seconds: 1));
      } finally {
        mail.close();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await di.reset();
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
