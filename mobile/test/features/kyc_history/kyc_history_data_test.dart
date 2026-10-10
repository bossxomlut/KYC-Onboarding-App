import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/core/domain/result.dart';
import 'package:kyc_onboarding/core/network/api_client.dart';
import 'package:kyc_onboarding/features/auth/domain/entities/user.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';
import 'package:kyc_onboarding/features/kyc_history/data/datasources/kyc_history_remote_datasource.dart';
import 'package:kyc_onboarding/features/kyc_history/data/models/kyc_history_model.dart';
import 'package:kyc_onboarding/features/kyc_history/data/repositories/kyc_history_repository_impl.dart';
import '../auth/data/session_restore_test.dart' show TestAdapter, jsonResponse;

void main() {
  test('legacy reviewer identity accepts missing email and role snapshots', () {
    final review = Map<String, dynamic>.from(submissionJson['review'] as Map);
    review['reviewer'] = {'id': 'legacy-reviewer', 'email': null, 'role': null};
    final submission = KycHistoryModel.submission({
      ...submissionJson,
      'review': review,
    });
    expect(submission.review!.reviewer!.id, 'legacy-reviewer');
    expect(submission.review!.reviewer!.email, isNull);
    expect(submission.review!.reviewer!.role, isNull);
  });
  test('history keeps rejected snapshot and its reviewer identity', () {
    final submission = KycHistoryModel.submission(submissionJson);
    expect(submission.version, 1);
    expect(submission.profile.status, KycStatus.rejected);
    expect(submission.profile.personalDetails!.fullName, 'Original Applicant');
    expect(submission.profile.document!.id, 'original-document');
    expect(submission.review!.reviewer!.email, 'reviewer@example.test');
    expect(submission.review!.reviewer!.role, UserRole.reviewer);
    expect(submission.review!.requiredSteps, [KycStep.document]);
    expect(submission.review!.reason, 'The document is blurred.');
  });

  test(
    'authenticated history requests page and immutable submission photos',
    () async {
      final dio = Dio(
        BaseOptions(
          baseUrl: 'https://example.test/api/v1',
          headers: {'Authorization': 'Bearer test-token'},
        ),
      );
      final requests = <RequestOptions>[];
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aSu8AAAAASUVORK5CYII=',
      );
      dio.httpClientAdapter = TestAdapter((options) {
        requests.add(options);
        if (options.uri.path.contains('/media/')) {
          return ResponseBody.fromBytes(
            bytes,
            200,
            headers: {
              Headers.contentTypeHeader: ['image/png'],
            },
          );
        }
        return jsonResponse({
          'submissions': [submissionJson],
          'total': 23,
        });
      });
      final repository = KycHistoryRepositoryImpl(
        KycHistoryRemoteDataSource(ApiClient(dio)),
      );
      final page = await repository.load(offset: 20);
      expect(page, isA<Success>());
      expect(requests.last.uri.path, '/api/v1/kyc/history');
      expect(requests.last.uri.queryParameters, {
        'limit': '20',
        'offset': '20',
      });
      final image = await repository.media('submission-1', MediaKind.document);
      expect((image as Success).value, bytes);
      expect(
        requests.last.uri.path,
        '/api/v1/kyc/history/submission-1/media/document',
      );
      await repository.load(reviewerUserId: 'applicant');
      expect(requests.last.uri.path, '/api/v1/reviews/applicant/history');
      await repository.media(
        'submission-1',
        MediaKind.selfie,
        reviewerUserId: 'applicant',
      );
      expect(
        requests.last.uri.path,
        '/api/v1/reviews/applicant/history/submission-1/media/selfie',
      );
      expect(
        requests.every(
          (request) => request.headers['Authorization'] == 'Bearer test-token',
        ),
        isTrue,
      );
    },
  );

  test('history transport failures become typed failures', () async {
    final dio = Dio();
    dio.httpClientAdapter = TestAdapter(
      (options) => throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      ),
    );
    final repository = KycHistoryRepositoryImpl(
      KycHistoryRemoteDataSource(ApiClient(dio)),
    );
    final result = await repository.load();
    expect((result as Failure).error.code, 'NETWORK_ERROR');
  });
}

final submissionJson = <String, dynamic>{
  'id': 'submission-1',
  'version': 1,
  'profile': {
    'id': 'profile',
    'status': 'rejected',
    'nextStep': 'result',
    'personalDetails': {
      'fullName': 'Original Applicant',
      'dateOfBirth': '1990-03-10',
      'nationality': 'Vietnamese',
      'address': '1 Original Street',
      'documentNumber': 'OLD1234',
    },
    'document': {
      'id': 'original-document',
      'mimeType': 'image/png',
      'size': 68,
      'documentType': 'passport',
    },
    'selfie': {'id': 'original-selfie', 'mimeType': 'image/png', 'size': 68},
    'rejectionReason': 'The document is blurred.',
    'requiredSteps': ['document'],
    'submittedAt': '2026-10-09T08:00:00.000Z',
  },
  'review': {
    'decision': 'rejected',
    'reason': 'The document is blurred.',
    'requiredSteps': ['document'],
    'reviewedAt': '2026-10-09T09:00:00.000Z',
    'reviewer': {
      'id': 'reviewer-1',
      'email': 'reviewer@example.test',
      'role': 'reviewer',
    },
  },
};
