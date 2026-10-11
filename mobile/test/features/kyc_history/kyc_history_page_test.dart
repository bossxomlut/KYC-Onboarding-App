import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/features/kyc/presentation/widgets/verification_summary.dart';
import 'package:kyc_onboarding/features/kyc_history/presentation/bloc/kyc_history_cubit.dart';
import 'package:kyc_onboarding/features/kyc_history/presentation/pages/kyc_history_page.dart';
import 'kyc_history_cubit_test.dart'
    show FakeHistoryRepository, historyCubit, networkFailure;
import 'kyc_history_data_test.dart' show submissionJson;

void main() {
  for (final status in ['completed', 'failed']) {
    testWidgets('applicant history hides $status identity evidence', (
      tester,
    ) async {
      final repository = FakeHistoryRepository()
        ..submissionOverride = _submissionWithChecks(status);
      await pumpHistory(tester, repository);
      await tester.tap(
        find.byKey(const Key('history-submission-submission-1')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(VerificationSummary), findsNothing);
      expect(find.text('OCR NAME ONLY'), findsNothing);
      expect(find.text('OCR123456'), findsNothing);
      expect(find.textContaining('62.8'), findsNothing);
      expect(find.text('Original Applicant'), findsOneWidget);
      expect(find.text('OLD1234'), findsOneWidget);
      expect(repository.reviewerUserIds, everyElement(isNull));
      await tester.tap(find.byKey(const Key('history-detail-close')));
      await tester.pumpAndSettle();
      expect(find.text('Submission history'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reviewer history displays the recorded identity values', (
    tester,
  ) async {
    final repository = FakeHistoryRepository()
      ..submissionOverride = _submissionWithChecks('completed');
    await pumpHistory(tester, repository, reviewerUserId: 'applicant');
    await tester.tap(find.byKey(const Key('history-submission-submission-1')));
    await tester.pumpAndSettle();

    expect(find.byType(VerificationSummary), findsOneWidget);
    expect(find.text('OCR NAME ONLY'), findsOneWidget);
    expect(find.text('OCR123456'), findsOneWidget);
    expect(find.textContaining('62.8'), findsOneWidget);
    expect(find.text('Original Applicant'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    expect(repository.reviewerUserIds, everyElement('applicant'));
    await tester.tap(find.byKey(const Key('history-detail-close')));
    await tester.pumpAndSettle();
    expect(find.text('Submission history'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reviewer history never manufactures missing identity evidence', (
    tester,
  ) async {
    await pumpHistory(
      tester,
      FakeHistoryRepository(),
      reviewerUserId: 'applicant',
    );
    await tester.tap(find.byKey(const Key('history-submission-submission-1')));
    await tester.pumpAndSettle();

    expect(find.byType(VerificationSummary), findsNothing);
    expect(find.textContaining('62.8'), findsNothing);
    expect(find.text('Original Applicant'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'history and its detail remain usable at narrow width and double text size',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpHistory(tester, FakeHistoryRepository(), textScale: 2);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(
        find.byKey(const Key('history-submission-submission-1')),
      );
      await tester.tap(
        find.byKey(const Key('history-submission-submission-1')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('history-detail-close')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('history-detail-close')));
      await tester.pumpAndSettle();
      expect(find.text('Submission history'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'final legacy round retains rejected reason without a review audit',
    (tester) async {
      final repository = FakeHistoryRepository()
        ..submissionOverride = {...submissionJson, 'review': null};
      await pumpHistory(tester, repository);
      expect(find.text('Awaiting review'), findsNothing);
      expect(
        find.text(
          'Review information unavailable for this historical submission.',
        ),
        findsOneWidget,
      );
      expect(find.text('The document is blurred.'), findsOneWidget);
      expect(
        find.textContaining('Requested updates: ID document'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'history shows original rejected details, reviewer and private images read only',
    (tester) async {
      final repository = FakeHistoryRepository();
      await pumpHistory(tester, repository);
      expect(find.text('Submission history'), findsOneWidget);
      expect(find.text('Submission #1'), findsOneWidget);
      expect(find.textContaining('reviewer@example.test'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('history-submission-submission-1')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Original Applicant'), findsOneWidget);
      expect(find.text('OLD1234'), findsOneWidget);
      expect(find.textContaining('The document is blurred.'), findsWidgets);
      expect(find.textContaining('ID document'), findsWidgets);
      expect(find.text('Edit'), findsNothing);
      expect(repository.mediaCalls, [
        'submission-1/document',
        'submission-1/selfie',
      ]);
      final images = tester
          .widgetList<Image>(find.byType(Image))
          .where((image) => image.image is MemoryImage)
          .toList();
      expect(images, hasLength(2));
      expect(
        images.every(
          (image) =>
              listEquals((image.image as MemoryImage).bytes, repository.image),
        ),
        isTrue,
      );
      await tester.tap(find.byKey(const Key('history-detail-close')));
      await tester.pumpAndSettle();
      expect(find.text('Original Applicant'), findsNothing);
    },
  );

  testWidgets('history photo failure can retry inside the detail sheet', (
    tester,
  ) async {
    final repository = FakeHistoryRepository()..failSelfie = true;
    await pumpHistory(tester, repository);
    await tester.tap(find.byKey(const Key('history-submission-submission-1')));
    await tester.pumpAndSettle();
    expect(find.text(networkFailure.message), findsOneWidget);
    repository.failSelfie = false;
    await tester.ensureVisible(find.byKey(const Key('history-media-retry')));
    await tester.tap(find.byKey(const Key('history-media-retry')));
    await tester.pumpAndSettle();
    expect(find.text(networkFailure.message), findsNothing);
    expect(find.byType(Image), findsNWidgets(2));
  });

  testWidgets('history handles empty results and retryable list errors', (
    tester,
  ) async {
    final repository = FakeHistoryRepository()..loadError = networkFailure;
    await pumpHistory(tester, repository);
    expect(find.text(networkFailure.message), findsOneWidget);
    repository
      ..loadError = null
      ..total = 0;
    await tester.tap(find.byKey(const Key('history-list-retry')));
    await tester.pumpAndSettle();
    expect(find.text('No submissions yet.'), findsOneWidget);
  });

  testWidgets('Load more keeps existing rounds and appends the next page', (
    tester,
  ) async {
    final repository = FakeHistoryRepository()..total = 2;
    await pumpHistory(tester, repository);
    await tester.ensureVisible(find.byKey(const Key('history-load-more')));
    await tester.tap(find.byKey(const Key('history-load-more')));
    await tester.pumpAndSettle();
    expect(find.text('Submission #1'), findsOneWidget);
    expect(find.text('Submission #2'), findsOneWidget);
    expect(find.byKey(const Key('history-load-more')), findsNothing);
  });
}

Future<void> pumpHistory(
  WidgetTester tester,
  FakeHistoryRepository repository, {
  double textScale = 1,
  String? reviewerUserId,
}) async {
  final cubit = historyCubit(repository);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await cubit.close();
  });
  await tester.pumpWidget(
    BlocProvider<KycHistoryCubit>.value(
      value: cubit,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: KycHistoryPage(reviewerUserId: reviewerUserId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Map<String, dynamic> _submissionWithChecks(String status) => {
  ...submissionJson,
  'profile': {
    ...Map<String, dynamic>.from(submissionJson['profile'] as Map),
    'verification': {
      'provider': 'local',
      'status': status,
      'documentId': 'original-document',
      'selfieId': 'original-selfie',
      'checkedAt': '2026-10-09T07:59:00.000Z',
      'selfieFace': {'status': 'detected'},
      'ocr': {
        'status': 'succeeded',
        'text': 'OCR NAME ONLY OCR123456',
        'fields': {
          'fullName': 'OCR NAME ONLY',
          'dateOfBirth': '1994-05-16',
          'documentNumber': 'OCR123456',
        },
        'confidence': 87.5,
      },
      'faceMatch': {'status': 'matched', 'similarity': 62.8, 'threshold': 36.3},
    },
  },
};
