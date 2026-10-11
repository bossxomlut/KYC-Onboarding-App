import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';
import 'package:kyc_onboarding/features/kyc/presentation/widgets/kyc_profile_summary.dart';
import 'package:kyc_onboarding/features/kyc/presentation/widgets/verification_summary.dart';

void main() {
  for (final status in [
    VerificationStatus.completed,
    VerificationStatus.failed,
  ]) {
    testWidgets('default summary hides ${status.name} identity evidence', (
      tester,
    ) async {
      KycStep? edited;
      await _pump(
        tester,
        KycProfileSummary(
          profile: _profile(status),
          media: const {},
          onEdit: (step) => edited = step,
        ),
      );

      expect(find.byType(VerificationSummary), findsNothing);
      expect(find.text('OCR NAME ONLY'), findsNothing);
      expect(find.text('OCR123456'), findsNothing);
      expect(find.textContaining('62.8'), findsNothing);
      expect(find.text('Applicant Name'), findsOneWidget);
      expect(find.text('APP1234'), findsOneWidget);
      expect(find.text('Verification status'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Edit').first);
      expect(edited, KycStep.personalDetails);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reviewer opt-in preserves the recorded identity values', (
    tester,
  ) async {
    await _pump(
      tester,
      KycProfileSummary(
        profile: _profile(VerificationStatus.completed),
        media: const {},
        showVerification: true,
      ),
    );

    expect(find.byType(VerificationSummary), findsOneWidget);
    expect(find.text('OCR NAME ONLY'), findsOneWidget);
    expect(find.text('OCR123456'), findsOneWidget);
    expect(find.textContaining('62.8'), findsOneWidget);
    expect(find.text('Applicant Name'), findsOneWidget);
    expect(find.text('APP1234'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

KycProfile _profile(VerificationStatus status) => KycProfile(
  id: 'profile',
  status: KycStatus.inProgress,
  nextStep: KycStep.review,
  personalDetails: const PersonalDetails(
    fullName: 'Applicant Name',
    dateOfBirth: '1990-03-10',
    nationality: 'Vietnamese',
    address: '1 Applicant Street',
    documentNumber: 'APP1234',
  ),
  document: const KycMedia(id: 'document', mimeType: 'image/jpeg', size: 100),
  selfie: const KycMedia(id: 'selfie', mimeType: 'image/jpeg', size: 100),
  verification: KycVerification(
    provider: 'local',
    status: status,
    documentId: 'document',
    selfieId: 'selfie',
    selfieFace: const SelfieFaceVerification(status: SelfieFaceStatus.detected),
    ocr: const OcrVerification(
      status: OcrStatus.succeeded,
      text: 'OCR NAME ONLY OCR123456',
      fields: OcrFields(fullName: 'OCR NAME ONLY', documentNumber: 'OCR123456'),
      confidence: 87.5,
    ),
    faceMatch: const FaceMatchVerification(
      status: FaceMatchStatus.matched,
      similarity: 62.8,
      threshold: 36.3,
    ),
  ),
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}
