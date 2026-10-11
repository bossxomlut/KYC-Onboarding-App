import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/core/domain/result.dart';
import 'package:kyc_onboarding/core/theme/app_theme.dart';
import 'package:kyc_onboarding/features/access/domain/entities/access_entities.dart';
import 'package:kyc_onboarding/features/access/domain/usecases/access_usecases.dart';
import 'package:kyc_onboarding/features/access/presentation/bloc/access_cubit.dart';
import 'package:kyc_onboarding/features/access/presentation/pages/reviewer_detail_page.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';
import 'package:kyc_onboarding/features/kyc/presentation/widgets/kyc_profile_summary.dart';
import 'package:kyc_onboarding/features/kyc/presentation/widgets/verification_summary.dart';

import '../access/access_cubit_test.dart' show FakeAccessRepository;

const _recognizedText = 'SAMPLE PERSON\nDOB 1994-02-10\nID SAMPLE123';
const _completed = KycVerification(
  provider: 'aws',
  status: VerificationStatus.completed,
  documentId: 'document',
  selfieId: 'selfie',
  ocr: OcrVerification(
    status: OcrStatus.succeeded,
    text: _recognizedText,
    fields: OcrFields(
      fullName: 'SAMPLE PERSON',
      dateOfBirth: '1994-02-10',
      documentNumber: 'SAMPLE123',
    ),
    confidence: 96.4,
  ),
  faceMatch: FaceMatchVerification(
    status: FaceMatchStatus.matched,
    similarity: 97.2,
    threshold: 90,
  ),
);

void main() {
  testWidgets('legacy profiles do not show an empty automated checks panel', (
    tester,
  ) async {
    await _pump(tester, const VerificationSummary(verification: null));
    expect(find.text('Automated checks'), findsNothing);
    expect(find.text('Document text (OCR)'), findsNothing);
  });

  testWidgets('disabled checks explain manual review without empty results', (
    tester,
  ) async {
    await _pump(
      tester,
      const VerificationSummary(
        verification: KycVerification(
          provider: 'none',
          status: VerificationStatus.disabled,
        ),
      ),
    );
    expect(
      find.textContaining('Automated checks are unavailable.'),
      findsOneWidget,
    );
    expect(find.textContaining('reviewer'), findsOneWidget);
    expect(find.text('Document text (OCR)'), findsNothing);
    expect(find.text('Face comparison'), findsNothing);
  });

  testWidgets(
    'not-started checks communicate that these photos are unchecked',
    (tester) async {
      await _pump(
        tester,
        const VerificationSummary(
          verification: KycVerification(
            provider: 'aws',
            status: VerificationStatus.notStarted,
          ),
        ),
      );
      expect(
        find.text('Automated checks have not run for these photos yet.'),
        findsOneWidget,
      );
      expect(find.text('Faces are similar'), findsNothing);
    },
  );

  testWidgets('extracted fields and scores are read-only; raw text expands', (
    tester,
  ) async {
    await _pump(tester, const VerificationSummary(verification: _completed));
    expect(find.text('SAMPLE PERSON'), findsOneWidget);
    expect(find.text('1994-02-10'), findsOneWidget);
    expect(find.text('SAMPLE123'), findsOneWidget);
    expect(find.text('OCR confidence: 96.4%'), findsOneWidget);
    expect(find.text('Similarity score: 97.2 / 100'), findsOneWidget);
    expect(find.text('Match threshold: 90 / 100'), findsOneWidget);
    expect(find.textContaining('does not check liveness'), findsOneWidget);
    expect(
      find.textContaining('reviewer makes the final decision'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.text(_recognizedText), findsNothing);
    await tester.ensureVisible(find.text('Recognized document text'));
    await tester.tap(find.text('Recognized document text'));
    await tester.pumpAndSettle();
    expect(find.text(_recognizedText), findsOneWidget);
  });

  testWidgets(
    'partial OCR keeps the extracted value without inventing others',
    (tester) async {
      await _pump(
        tester,
        const VerificationSummary(
          verification: KycVerification(
            provider: 'aws',
            status: VerificationStatus.completed,
            ocr: OcrVerification(
              status: OcrStatus.succeeded,
              text: 'ID SAMPLE123',
              fields: OcrFields(documentNumber: 'SAMPLE123'),
            ),
          ),
        ),
      );
      expect(find.text('SAMPLE123'), findsOneWidget);
      expect(find.text('Extracted full name'), findsNothing);
      expect(find.text('Extracted date of birth'), findsNothing);
      expect(find.textContaining('OCR confidence:'), findsNothing);
      expect(find.text('Face comparison unavailable.'), findsOneWidget);
    },
  );

  for (final entry in {
    OcrStatus.noText: 'No document text was recognized.',
    OcrStatus.failed: 'Document text recognition could not complete.',
  }.entries) {
    testWidgets('${entry.key.name} OCR does not display successful evidence', (
      tester,
    ) async {
      await _pump(
        tester,
        VerificationSummary(
          verification: KycVerification(
            provider: 'aws',
            status: VerificationStatus.failed,
            ocr: OcrVerification(
              status: entry.key,
              text: '',
              fields: const OcrFields(),
            ),
          ),
        ),
      );
      expect(find.text(entry.value), findsOneWidget);
      expect(
        find.textContaining('Automated checks could not complete.'),
        findsOneWidget,
      );
      expect(find.text('Recognized document text'), findsNothing);
      expect(find.textContaining('OCR confidence:'), findsNothing);
    });
  }

  for (final entry in {
    FaceMatchStatus.notMatched: 'Faces are below the match threshold',
    FaceMatchStatus.noFace:
        'A face could not be detected in one or both photos.',
    FaceMatchStatus.multipleFaces:
        'Multiple faces were detected. Review the photos manually.',
    FaceMatchStatus.failed: 'Face comparison could not complete.',
  }.entries) {
    testWidgets(
      '${entry.key.name} requires review without a fabricated score',
      (tester) async {
        await _pump(
          tester,
          VerificationSummary(
            verification: KycVerification(
              provider: 'aws',
              status: VerificationStatus.completed,
              faceMatch: FaceMatchVerification(
                status: entry.key,
                threshold: 90,
              ),
            ),
          ),
        );
        expect(find.text(entry.value), findsOneWidget);
        expect(find.textContaining('Similarity score:'), findsNothing);
        expect(
          find.textContaining('reviewer makes the final decision'),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets('applicant summary preserves its existing manual edit action', (
    tester,
  ) async {
    KycStep? edited;
    await _pump(
      tester,
      KycProfileSummary(
        profile: const KycProfile(
          id: 'profile',
          status: KycStatus.inProgress,
          nextStep: KycStep.review,
          document: KycMedia(id: 'document', mimeType: 'image/jpeg', size: 100),
          selfie: KycMedia(id: 'selfie', mimeType: 'image/jpeg', size: 100),
          verification: _completed,
        ),
        media: const {},
        onEdit: (step) => edited = step,
      ),
    );
    expect(find.text('Automated checks'), findsOneWidget);
    expect(find.text('Faces are similar'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Edit').first);
    expect(edited, KycStep.personalDetails);
  });

  for (final verification in [
    _completed,
    const KycVerification(provider: 'aws', status: VerificationStatus.failed),
  ]) {
    testWidgets(
      'reviewer sees ${verification.status.name} evidence and still decides manually',
      (tester) async {
        final repository = _ReviewRepository(verification);
        final cubit = AccessCubit(AccessUseCases(repository));
        addTearDown(cubit.close);
        await cubit.loadDetail('applicant');
        await tester.pumpWidget(
          BlocProvider.value(
            value: cubit,
            child: MaterialApp(
              theme: AppTheme.light,
              home: const ReviewerDetailPage(
                userId: 'applicant',
                actorId: 'reviewer',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Automated checks'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('review-approve')))
              .onPressed,
          isNotNull,
        );
        expect(
          tester
              .widget<OutlinedButton>(find.byKey(const Key('review-reject')))
              .onPressed,
          isNotNull,
        );
        expect(repository.decisions, 0);
        expect(cubit.state.detail!.profile.status, KycStatus.pendingReview);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'completed evidence wraps at 320px with large text and expansion',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pump(
        tester,
        const VerificationSummary(verification: _completed),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Recognized document text'));
      await tester.tap(find.text('Recognized document text'));
      await tester.pumpAndSettle();
      expect(find.text(_recognizedText), findsOneWidget);
      await tester.ensureVisible(
        find.textContaining('does not check liveness'),
      );
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: child,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _ReviewRepository extends FakeAccessRepository {
  _ReviewRepository(this.verification);
  final KycVerification verification;

  @override
  Future<Result<ReviewDetail>> reviewDetail(String userId) async => Success(
    ReviewDetail(
      submissionId: 'submission',
      userId: userId,
      email: 'sample@example.test',
      profile: KycProfile(
        id: 'profile',
        status: KycStatus.pendingReview,
        nextStep: KycStep.result,
        document: const KycMedia(
          id: 'document',
          mimeType: 'image/png',
          size: 68,
        ),
        selfie: const KycMedia(id: 'selfie', mimeType: 'image/png', size: 68),
        verification: verification,
      ),
    ),
  );

  @override
  Future<Result<Uint8List>> reviewMedia(
    String userId,
    MediaKind kind, {
    required String submissionId,
  }) async => Success(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aSu8AAAAASUVORK5CYII=',
    ),
  );
}
