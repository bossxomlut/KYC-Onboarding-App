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
  selfieFace: SelfieFaceVerification(status: SelfieFaceStatus.detected),
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
  testWidgets('failed attempt without component evidence shows check failure', (
    tester,
  ) async {
    await _pump(
      tester,
      const VerificationSummary(
        verification: KycVerification(
          provider: 'local',
          status: VerificationStatus.failed,
        ),
      ),
    );
    expect(find.text('Check failed'), findsOneWidget);
    expect(find.text('Face detected'), findsNothing);
    expect(find.textContaining('Score '), findsNothing);
  });

  testWidgets('no match shows actual score and checked time compactly', (
    tester,
  ) async {
    await _pump(
      tester,
      VerificationSummary(
        verification: KycVerification(
          provider: 'local',
          status: VerificationStatus.completed,
          checkedAt: DateTime(2026, 10, 11, 10, 30),
          faceMatch: const FaceMatchVerification(
            status: FaceMatchStatus.notMatched,
            similarity: 8.941795557620935,
            threshold: 36.3,
          ),
        ),
      ),
    );
    expect(find.text('No match'), findsOneWidget);
    expect(find.text('Score 8.9 / 100 · threshold 36.3'), findsOneWidget);
    expect(find.text('Checked 11 Oct 2026, 10:30'), findsOneWidget);
    expect(find.textContaining('8.9%'), findsNothing);
    expect(find.text('Local identity checks'), findsNothing);
  });

  testWidgets('partial failure retains actual OCR fields and detected selfie', (
    tester,
  ) async {
    await _pump(
      tester,
      const VerificationSummary(
        verification: KycVerification(
          provider: 'local',
          status: VerificationStatus.failed,
          ocr: OcrVerification(
            status: OcrStatus.failed,
            text: 'ID SAMPLE123',
            fields: OcrFields(documentNumber: 'SAMPLE123'),
          ),
          selfieFace: SelfieFaceVerification(status: SelfieFaceStatus.detected),
        ),
      ),
    );
    expect(find.text('SAMPLE123'), findsOneWidget);
    expect(find.text('Check failed'), findsOneWidget);
    expect(find.text('Face detected'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(2));
    await tester.ensureVisible(find.text('OCR text'));
    await tester.tap(find.text('OCR text'));
    await tester.pumpAndSettle();
    expect(find.text('ID SAMPLE123'), findsOneWidget);
  });

  testWidgets('selfie presence and document comparison appear separately', (
    tester,
  ) async {
    await _pump(tester, const VerificationSummary(verification: _completed));
    expect(find.text('Selfie'), findsOneWidget);
    expect(find.text('Face detected'), findsOneWidget);
    expect(find.text('Face match'), findsOneWidget);
    expect(find.text('Match'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Selfie')).dy,
      lessThan(tester.getTopLeft(find.text('Face match')).dy),
    );
    expect(find.textContaining('No liveness check'), findsOneWidget);
  });

  for (final entry in {
    SelfieFaceStatus.noFace: 'No face',
    SelfieFaceStatus.multipleFaces: 'Multiple faces',
    SelfieFaceStatus.failed: 'Check failed',
  }.entries) {
    testWidgets('${entry.key.name} selfie result is explicit', (tester) async {
      await _pump(
        tester,
        VerificationSummary(
          verification: KycVerification(
            provider: 'local',
            status: entry.key == SelfieFaceStatus.failed
                ? VerificationStatus.failed
                : VerificationStatus.completed,
            selfieFace: SelfieFaceVerification(status: entry.key),
            faceMatch: FaceMatchVerification(
              status: entry.key == SelfieFaceStatus.multipleFaces
                  ? FaceMatchStatus.multipleFaces
                  : entry.key == SelfieFaceStatus.failed
                  ? FaceMatchStatus.failed
                  : FaceMatchStatus.noFace,
              threshold: 36.3,
            ),
          ),
        ),
      );
      expect(find.text('Selfie'), findsOneWidget);
      expect(find.text(entry.value), findsNWidgets(2));
      expect(find.text('Face detected'), findsNothing);
      expect(find.text('Match'), findsNothing);
      expect(find.textContaining('Score '), findsNothing);
      expect(find.textContaining('No liveness check'), findsOneWidget);
    });
  }

  testWidgets('selfie detection can succeed when document comparison cannot', (
    tester,
  ) async {
    await _pump(
      tester,
      const VerificationSummary(
        verification: KycVerification(
          provider: 'local',
          status: VerificationStatus.completed,
          selfieFace: SelfieFaceVerification(status: SelfieFaceStatus.detected),
          faceMatch: FaceMatchVerification(
            status: FaceMatchStatus.noFace,
            threshold: 36.3,
          ),
        ),
      ),
    );
    expect(find.text('Face detected'), findsOneWidget);
    expect(find.text('No face'), findsOneWidget);
    expect(find.text('Match'), findsNothing);
    expect(find.textContaining('Score '), findsNothing);
  });

  testWidgets('legacy checks never infer recorded selfie face evidence', (
    tester,
  ) async {
    await _pump(
      tester,
      const VerificationSummary(
        verification: KycVerification(
          provider: 'aws',
          status: VerificationStatus.completed,
          faceMatch: FaceMatchVerification(
            status: FaceMatchStatus.matched,
            threshold: 90,
            similarity: 97,
          ),
        ),
      ),
    );
    expect(find.text('Not recorded'), findsOneWidget);
    expect(find.text('Face detected'), findsNothing);
    expect(find.text('Match'), findsOneWidget);
  });

  testWidgets('legacy profiles do not show an empty automated checks panel', (
    tester,
  ) async {
    await _pump(tester, const VerificationSummary(verification: null));
    expect(find.text('Identity checks'), findsNothing);
    expect(find.text('OCR'), findsNothing);
  });

  testWidgets('disabled checks show a compact unavailable status', (
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
    expect(find.textContaining('Unavailable'), findsOneWidget);
    expect(find.textContaining('reviewer'), findsNothing);
    expect(find.text('OCR'), findsNothing);
    expect(find.text('Face match'), findsNothing);
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
      expect(find.text('Not run'), findsOneWidget);
      expect(find.text('Match'), findsNothing);
    },
  );

  testWidgets('extracted fields and scores are read-only; raw text expands', (
    tester,
  ) async {
    await _pump(tester, const VerificationSummary(verification: _completed));
    expect(find.text('SAMPLE PERSON'), findsOneWidget);
    expect(find.text('1994-02-10'), findsOneWidget);
    expect(find.text('SAMPLE123'), findsOneWidget);
    expect(find.text('Extracted · 96.4% confidence'), findsOneWidget);
    expect(find.text('Score 97.2 / 100 · threshold 90'), findsOneWidget);
    expect(find.text('97.2%'), findsNothing);
    expect(find.textContaining('No liveness check'), findsOneWidget);
    expect(
      find.textContaining('reviewer makes the final decision'),
      findsNothing,
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.text(_recognizedText), findsNothing);
    await tester.ensureVisible(find.text('OCR text'));
    await tester.tap(find.text('OCR text'));
    await tester.pumpAndSettle();
    expect(find.text(_recognizedText), findsOneWidget);
  });

  testWidgets('local results show actual data without provider branding', (
    tester,
  ) async {
    await _pump(
      tester,
      const VerificationSummary(
        verification: KycVerification(
          provider: 'local',
          status: VerificationStatus.completed,
          ocr: OcrVerification(
            status: OcrStatus.succeeded,
            text: 'Họ và tên: NGUYỄN VĂN AN',
            fields: OcrFields(fullName: 'NGUYỄN VĂN AN'),
            confidence: 87.5,
          ),
          faceMatch: FaceMatchVerification(
            status: FaceMatchStatus.matched,
            similarity: 62.8,
            threshold: 45,
          ),
        ),
      ),
    );
    expect(find.text('Identity checks'), findsOneWidget);
    expect(find.text('NGUYỄN VĂN AN'), findsOneWidget);
    expect(find.text('Extracted · 87.5% confidence'), findsOneWidget);
    expect(find.text('Score 62.8 / 100 · threshold 45'), findsOneWidget);
    expect(find.text('62.8%'), findsNothing);
    expect(find.textContaining('not a probability of identity'), findsNothing);
    expect(find.textContaining('No liveness check'), findsOneWidget);
    expect(
      find.textContaining('reviewer makes the final decision'),
      findsNothing,
    );
    expect(find.byType(TextField), findsNothing);
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
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('—'), findsNWidgets(2));
      expect(find.text('Date of birth'), findsOneWidget);
      expect(find.textContaining('confidence'), findsNothing);
      expect(find.text('Unavailable'), findsOneWidget);
    },
  );

  for (final entry in {
    OcrStatus.noText: 'No text',
    OcrStatus.failed: 'Check failed',
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
      expect(find.text('—'), findsNWidgets(3));
      expect(find.text('OCR text'), findsNothing);
      expect(find.textContaining('confidence'), findsNothing);
    });
  }

  for (final entry in {
    FaceMatchStatus.notMatched: 'No match',
    FaceMatchStatus.noFace: 'No face',
    FaceMatchStatus.multipleFaces: 'Multiple faces',
    FaceMatchStatus.failed: 'Check failed',
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
        expect(find.textContaining('Score '), findsNothing);
        expect(
          find.textContaining('reviewer makes the final decision'),
          findsNothing,
        );
      },
    );
  }

  testWidgets('applicant summary hides checks and preserves its edit action', (
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
    expect(find.text('Identity checks'), findsNothing);
    expect(find.text('Match'), findsNothing);
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
        expect(find.text('Identity checks'), findsOneWidget);
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
      await tester.ensureVisible(find.text('OCR text'));
      await tester.tap(find.text('OCR text'));
      await tester.pumpAndSettle();
      expect(find.text(_recognizedText), findsOneWidget);
      await tester.ensureVisible(find.textContaining('No liveness check'));
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
