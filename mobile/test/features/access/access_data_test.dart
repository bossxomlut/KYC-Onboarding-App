import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/core/domain/result.dart';
import 'package:kyc_onboarding/core/network/api_client.dart';
import 'package:kyc_onboarding/features/access/data/datasources/access_remote_datasource.dart';
import 'package:kyc_onboarding/features/access/data/models/access_models.dart';
import 'package:kyc_onboarding/features/access/data/repositories/access_repository_impl.dart';
import 'package:kyc_onboarding/features/access/domain/entities/access_entities.dart';
import 'package:kyc_onboarding/features/access/domain/usecases/access_usecases.dart';
import 'package:kyc_onboarding/features/auth/domain/entities/user.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';

class _Api extends ApiClient {
  _Api() : super(Dio());
  String? path;
  Map<String, dynamic>? body;
  Map<String, dynamic> response = {};
  Object? error;
  int getCalls = 0;
  @override
  Future<Map<String, dynamic>> get(String path) async {
    getCalls++;
    this.path = path;
    if (error != null) throw error!;
    return response;
  }

  @override
  Future<Uint8List> bytes(String path) async {
    this.path = path;
    return Uint8List.fromList([1, 2]);
  }

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    this.path = path;
    body = data;
    if (error != null) throw error!;
    return response;
  }
}

void main() {
  group('review list filters and search', () {
    test('filters retain the API status values', () {
      expect(ReviewFilter.values.map((filter) => filter.apiValue), [
        'all',
        'pending_review',
        'verified',
        'rejected',
      ]);
    });

    test('summary maps review statuses and rejects unknown statuses', () {
      for (final entry in {
        'pending_review': KycStatus.pendingReview,
        'verified': KycStatus.verified,
        'rejected': KycStatus.rejected,
      }.entries) {
        final summary = AccessModels.summary({
          'userId': 'u',
          'email': 'u@example.test',
          'status': entry.key,
          'submittedAt': '2026-10-10T00:00:00.000Z',
        });
        expect(summary.status, entry.value);
      }
      expect(
        () => AccessModels.summary({
          'userId': 'u',
          'email': 'u@example.test',
          'status': 'approved',
        }),
        throwsFormatException,
      );
      expect(
        () => AccessModels.summary({'userId': 'u', 'email': 'u@example.test'}),
        throwsFormatException,
      );
    });

    test(
      'queue defaults to pending and leaves empty search out of the URI',
      () async {
        final api = _Api()..response = {'profiles': [], 'total': 0};
        final repository = AccessRepositoryImpl(AccessRemoteDataSource(api));

        final result = await repository.reviewQueue();

        expect(api.path, '/reviews?limit=50&offset=0&status=pending_review');
        expect(result, isA<Success<PageResult<ReviewSummary>>>());
        await repository.reviewQueue(search: '   ');
        expect(
          Uri.parse(api.path!).queryParameters.containsKey('search'),
          isFalse,
        );
      },
    );

    test(
      'queue encodes trimmed search and preserves filter and pagination',
      () async {
        final api = _Api()
          ..response = {
            'total': 101,
            'profiles': [
              {
                'userId': 'u',
                'email': 'u+review@example.test',
                'status': 'verified',
                'submittedAt': '2026-10-10T00:00:00.000Z',
              },
            ],
          };
        final useCases = AccessUseCases(
          AccessRepositoryImpl(AccessRemoteDataSource(api)),
        );
        const search = '  Nguyễn + % & ? / # @example.test  ';

        final result =
            await useCases.reviewQueue(
                  offset: 50,
                  filter: ReviewFilter.approved,
                  search: search,
                )
                as Success<PageResult<ReviewSummary>>;

        final uri = Uri.parse(api.path!);
        expect(uri.path, '/reviews');
        expect(uri.fragment, isEmpty);
        expect(uri.queryParameters, {
          'limit': '50',
          'offset': '50',
          'status': 'verified',
          'search': search.trim(),
        });
        expect(result.value.offset, 50);
        expect(result.value.total, 101);
        expect(result.value.hasMore, isTrue);
        expect(result.value.items.single.status, KycStatus.verified);
      },
    );

    test('each filter is passed to the remote queue', () async {
      final api = _Api()..response = {'profiles': [], 'total': 0};
      final repository = AccessRepositoryImpl(AccessRemoteDataSource(api));

      for (final filter in ReviewFilter.values) {
        await repository.reviewQueue(filter: filter);
        expect(Uri.parse(api.path!).queryParameters['status'], filter.apiValue);
      }
    });

    test('invalid response status maps to a typed failure', () async {
      final api = _Api()
        ..response = {
          'profiles': [
            {'userId': 'u', 'email': 'u@example.test', 'status': 'unknown'},
          ],
          'total': 1,
        };
      final repository = AccessRepositoryImpl(AccessRemoteDataSource(api));

      final result = await repository.reviewQueue();

      expect(
        (result as Failure<PageResult<ReviewSummary>>).error.code,
        'UNEXPECTED_ERROR',
      );
    });

    test('queue maps permission and network failures', () async {
      final api = _Api();
      final repository = AccessRepositoryImpl(AccessRemoteDataSource(api));
      final request = RequestOptions(path: '/reviews');
      api.error = DioException(
        requestOptions: request,
        response: Response(
          requestOptions: request,
          statusCode: 403,
          data: {
            'error': {'code': 'FORBIDDEN', 'message': 'Permission revoked'},
          },
        ),
      );

      final denied = await repository.reviewQueue(filter: ReviewFilter.all);
      expect(
        (denied as Failure<PageResult<ReviewSummary>>).error.code,
        'FORBIDDEN',
      );
      api.error = DioException(
        requestOptions: request,
        type: DioExceptionType.connectionError,
      );
      final disconnected = await repository.reviewQueue(search: 'applicant');
      expect(
        (disconnected as Failure<PageResult<ReviewSummary>>).error.isNetwork,
        isTrue,
      );
    });

    test(
      'search above 254 characters returns validation without HTTP',
      () async {
        final api = _Api()..response = {'profiles': [], 'total': 0};
        final useCases = AccessUseCases(
          AccessRepositoryImpl(AccessRemoteDataSource(api)),
        );

        final result = await useCases.reviewQueue(search: 'a' * 255);

        expect(
          (result as Failure<PageResult<ReviewSummary>>).error.code,
          'VALIDATION',
        );
        expect(api.getCalls, 0);
        final accepted = await useCases.reviewQueue(search: '  ${'a' * 254}  ');
        expect(accepted, isA<Success<PageResult<ReviewSummary>>>());
        expect(Uri.parse(api.path!).queryParameters['search'], 'a' * 254);
        expect(api.getCalls, 1);
      },
    );
  });

  test(
    'review detail and private photo requests preserve the submission identity',
    () async {
      final api = _Api()
        ..response = {
          'submissionId': 'submission-1',
          'user': {'id': 'u', 'email': 'u@example.test'},
          'profile': {
            'id': 'p',
            'status': 'pending_review',
            'nextStep': 'result',
            'requiredSteps': <String>[],
          },
        };
      final repository = AccessRepositoryImpl(AccessRemoteDataSource(api));
      final detail =
          await repository.reviewDetail('u') as Success<ReviewDetail>;
      expect(detail.value.submissionId, 'submission-1');
      await repository.reviewMedia(
        'u',
        MediaKind.selfie,
        submissionId: detail.value.submissionId,
      );
      expect(api.path, '/reviews/u/media/selfie?submissionId=submission-1');
    },
  );
  test(
    'paginated pending requests map status, user and decision metadata',
    () async {
      final api = _Api()
        ..response = {
          'total': 51,
          'requests': [
            {
              'id': 'req',
              'userId': 'u',
              'email': 'u@example.test',
              'status': 'pending',
              'reason': 'Need reviewer access',
              'createdAt': '2026-10-10T00:00:00.000Z',
            },
          ],
        };
      final repo = AccessRepositoryImpl(AccessRemoteDataSource(api));
      final result =
          await repo.requests(offset: 50) as Success<PageResult<RoleRequest>>;
      expect(api.path, '/admin/role-requests?limit=50&offset=50');
      expect(result.value.offset, 50);
      expect(result.value.items.single.status, RoleRequestStatus.pending);
      expect(result.value.items.single.email, 'u@example.test');
      expect(result.value.hasMore, isFalse);
    },
  );
  test(
    'admin creation preserves required email verification and selected role',
    () async {
      final api = _Api()
        ..response = {
          'user': {
            'id': 'u',
            'email': 'u@example.test',
            'emailVerified': false,
            'role': 'reviewer',
          },
          'nextStep': 'VERIFY_EMAIL',
        };
      final repo = AccessRepositoryImpl(AccessRemoteDataSource(api));
      final result =
          await repo.createUser(
                email: 'u@example.test',
                password: 'FakePassword123',
                role: UserRole.reviewer,
              )
              as Success<User>;
      expect(api.path, '/admin/users');
      expect(api.body?['role'], 'reviewer');
      expect(result.value.emailVerified, isFalse);
    },
  );
  test(
    'rejection maps personal details step and permission error to typed result',
    () async {
      final api = _Api()
        ..error = DioException(
          requestOptions: RequestOptions(path: '/reviews/u/decision'),
          response: Response(
            requestOptions: RequestOptions(path: '/reviews/u/decision'),
            statusCode: 403,
            data: {
              'error': {'code': 'FORBIDDEN', 'message': 'Permission revoked'},
            },
          ),
        );
      final repo = AccessRepositoryImpl(AccessRemoteDataSource(api));
      final result = await repo.decideProfile(
        'u',
        ReviewDecision.rejected,
        submissionId: 'submission-1',
        reason: 'Update the address',
        requiredSteps: [KycStep.personalDetails],
      );
      expect(api.body, {
        'submissionId': 'submission-1',
        'decision': 'rejected',
        'reason': 'Update the address',
        'requiredSteps': ['personal_details'],
      });
      expect((result as Failure<KycProfile>).error.code, 'FORBIDDEN');
    },
  );
}
