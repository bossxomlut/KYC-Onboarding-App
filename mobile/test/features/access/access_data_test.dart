import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/core/domain/result.dart';
import 'package:kyc_onboarding/core/network/api_client.dart';
import 'package:kyc_onboarding/features/access/data/datasources/access_remote_datasource.dart';
import 'package:kyc_onboarding/features/access/data/repositories/access_repository_impl.dart';
import 'package:kyc_onboarding/features/access/domain/entities/access_entities.dart';
import 'package:kyc_onboarding/features/auth/domain/entities/user.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';

class _Api extends ApiClient {
  _Api() : super(Dio());
  String? path;
  Map<String, dynamic>? body;
  Map<String, dynamic> response = {};
  Object? error;
  @override
  Future<Map<String, dynamic>> get(String path) async {
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
