import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/core/domain/result.dart';
import 'package:kyc_onboarding/core/network/api_client.dart';
import 'package:kyc_onboarding/features/kyc/data/datasources/kyc_remote_datasource.dart';
import 'package:kyc_onboarding/features/kyc/data/datasources/camera_datasource.dart';
import 'package:kyc_onboarding/features/kyc/data/models/kyc_profile_model.dart';
import 'package:kyc_onboarding/features/kyc/data/repositories/kyc_repository_impl.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';
import 'package:kyc_onboarding/features/kyc/domain/usecases/kyc_usecases.dart';
import 'package:kyc_onboarding/features/kyc/presentation/bloc/kyc_cubit.dart';
import 'package:kyc_onboarding/features/access/data/models/access_models.dart';
import 'package:kyc_onboarding/features/kyc_history/data/models/kyc_history_model.dart';

import 'kyc_cubit_test.dart' show FakeKycRepository, captured;

void main() {
  group('verification contract', () {
    for (final status in ['completed', 'failed']) {
      test(
        '$status evidence with changed or unknown source IDs is invalidated at the profile boundary',
        () {
          for (final sources in [
            {'documentId': 'old-document', 'selfieId': 'selfie'},
            {'documentId': 'document', 'selfieId': 'old-selfie'},
            {'documentId': null, 'selfieId': 'selfie'},
            {'documentId': 'document', 'selfieId': null},
          ]) {
            final json = completedJson()
              ..['status'] = status
              ..addAll(sources);
            final checks = KycProfileModel.fromJson(
              profileJson(json),
            ).verification!;
            expect(checks.status, VerificationStatus.notStarted);
            expect(checks.documentId, isNull);
            expect(checks.selfieId, isNull);
            expect(checks.ocr, isNull);
            expect(checks.faceMatch, isNull);
            expect(checks.checkedAt, isNull);
            expect(checks.provider, 'aws');
          }
        },
      );
    }

    test('missing current photos cannot validate completed evidence', () {
      final json = profileJson(completedJson())..['selfie'] = null;
      final checks = KycProfileModel.fromJson(json).verification!;
      expect(checks.status, VerificationStatus.notStarted);
      expect(checks.ocr, isNull);
      expect(checks.faceMatch, isNull);
    });

    test('unchecked status never carries results from a previous run', () {
      final json = completedJson()..['status'] = 'not_started';
      final checks = KycProfileModel.fromJson(profileJson(json)).verification!;
      expect(checks.status, VerificationStatus.notStarted);
      expect(checks.ocr, isNull);
      expect(checks.faceMatch, isNull);
      expect(checks.checkedAt, isNull);
    });

    test(
      'unchecked and disabled states retain their meaning without source IDs',
      () {
        for (final entry in {
          'not_started': VerificationStatus.notStarted,
          'disabled': VerificationStatus.disabled,
        }.entries) {
          final checks = KycProfileModel.fromJson(
            profileJson({
              'provider': entry.key == 'disabled' ? 'none' : 'aws',
              'status': entry.key,
              'documentId': null,
              'selfieId': null,
              'checkedAt': null,
              'ocr': null,
              'faceMatch': null,
            }),
          ).verification!;
          expect(checks.status, entry.value);
          expect(checks.ocr, isNull);
        }
      },
    );

    test('legacy profiles omit verification without changing submission', () {
      final profile = KycProfileModel.fromJson(profileJson());
      expect(profile.verification, isNull);
      expect(profile.canSubmit, isTrue);
    });

    test('maps OCR fields and advisory face scores on a completed profile', () {
      final profile = KycProfileModel.fromJson(profileJson(completedJson()));
      final checks = profile.verification!;
      expect(checks.provider, 'aws');
      expect(checks.status, VerificationStatus.completed);
      expect(checks.documentId, 'document');
      expect(checks.selfieId, 'selfie');
      expect(checks.checkedAt, DateTime.utc(2026, 10, 11));
      expect(checks.ocr!.status, OcrStatus.succeeded);
      expect(checks.ocr!.fields.fullName, 'DEMO USER');
      expect(checks.ocr!.fields.dateOfBirth, '1995-04-15');
      expect(checks.ocr!.fields.documentNumber, 'DEMO1234');
      expect(checks.ocr!.confidence, 98.5);
      expect(checks.faceMatch!.status, FaceMatchStatus.matched);
      expect(checks.faceMatch!.similarity, 97);
      expect(checks.faceMatch!.threshold, 90);
      expect(profile.status, KycStatus.inProgress);
      expect(profile.canSubmit, isTrue);
    });

    test('local evidence retains Vietnamese fields and advisory scores', () {
      final json = completedJson()
        ..['provider'] = 'local'
        ..['ocr'] = {
          'status': 'succeeded',
          'text': 'Họ và tên: NGUYỄN VĂN AN\nSố: 012345678901',
          'fields': {
            'fullName': 'NGUYỄN VĂN AN',
            'dateOfBirth': '1995-04-15',
            'documentNumber': '012345678901',
          },
          'confidence': 87.5,
        }
        ..['faceMatch'] = {
          'status': 'matched',
          'similarity': 62.8,
          'threshold': 45,
        };
      final profile = KycProfileModel.fromJson(profileJson(json));
      final checks = profile.verification!;
      expect(checks.provider, 'local');
      expect(checks.ocr!.fields.fullName, 'NGUYỄN VĂN AN');
      expect(checks.ocr!.fields.documentNumber, '012345678901');
      expect(checks.ocr!.confidence, 87.5);
      expect(checks.faceMatch!.similarity, 62.8);
      expect(checks.faceMatch!.threshold, 45);
      expect(profile.status, KycStatus.inProgress);
      expect(profile.canSubmit, isTrue);
    });

    test('maps disabled and failed checks, and rejects unknown statuses', () {
      final disabled = KycProfileModel.fromJson(
        profileJson({
          'provider': 'none',
          'status': 'disabled',
          'ocr': null,
          'faceMatch': null,
        }),
      ).verification!;
      expect(disabled.status, VerificationStatus.disabled);
      expect(disabled.ocr, isNull);
      final failed = completedJson()
        ..['status'] = 'failed'
        ..['ocr'] = {
          'status': 'failed',
          'text': '',
          'fields': {
            'fullName': null,
            'dateOfBirth': null,
            'documentNumber': null,
          },
          'confidence': null,
        }
        ..['faceMatch'] = {
          'status': 'no_face',
          'similarity': null,
          'threshold': 90,
        };
      final checks = KycProfileModel.fromJson(
        profileJson(failed),
      ).verification!;
      expect(checks.status, VerificationStatus.failed);
      expect(checks.ocr!.fields.fullName, isNull);
      expect(checks.faceMatch!.status, FaceMatchStatus.noFace);
      expect(
        () => KycProfileModel.fromJson(
          profileJson({'provider': 'aws', 'status': 'verified'}),
        ),
        throwsFormatException,
      );
    });

    test(
      'explicit remote verification posts once and maps its returned profile',
      () async {
        final api = _VerificationApi()
          ..response = {'profile': profileJson(completedJson())};
        final profile = await KycRemoteDataSource(api).verifyIdentity();
        expect(api.paths, ['/kyc/verification']);
        expect(api.body, isNull);
        expect(profile.verification!.status, VerificationStatus.completed);
        expect(profile.status, KycStatus.inProgress);
      },
    );

    test(
      'review detail and immutable history parse the same evidence contract',
      () {
        final json = profileJson(completedJson())
          ..['status'] = 'pending_review';
        final detail = AccessModels.detail({
          'submissionId': 'submission-1',
          'user': {'id': 'u', 'email': 'u@example.test'},
          'profile': json,
        });
        final history = KycHistoryModel.submission({
          'id': 'submission-1',
          'version': 1,
          'profile': json,
          'review': null,
        });
        expect(detail.profile.verification!.faceMatch!.similarity, 97);
        expect(
          history.profile.verification!.ocr!.fields.documentNumber,
          'DEMO1234',
        );
        expect(history.profile.canEdit, isFalse);
      },
    );

    test('all partial provider statuses map without fabricating scores', () {
      for (final entry in {
        'not_matched': FaceMatchStatus.notMatched,
        'no_face': FaceMatchStatus.noFace,
        'multiple_faces': FaceMatchStatus.multipleFaces,
        'failed': FaceMatchStatus.failed,
      }.entries) {
        final json = completedJson()
          ..['ocr'] = {
            'status': 'no_text',
            'text': '',
            'fields': {
              'fullName': null,
              'dateOfBirth': null,
              'documentNumber': null,
            },
            'confidence': null,
          }
          ..['faceMatch'] = {
            'status': entry.key,
            'similarity': null,
            'threshold': 90,
          };
        final checks = KycProfileModel.fromJson(
          profileJson(json),
        ).verification!;
        expect(checks.ocr!.status, OcrStatus.noText);
        expect(checks.faceMatch!.status, entry.value);
        expect(checks.faceMatch!.similarity, isNull);
      }
      final invalid = completedJson()
        ..['faceMatch'] = {
          'status': 'matched',
          'similarity': 101,
          'threshold': 90,
        };
      expect(
        () => KycProfileModel.fromJson(profileJson(invalid)),
        throwsFormatException,
      );
    });

    test(
      'repository maps provider unavailable and connectivity failures to domain results',
      () async {
        final api = _VerificationApi();
        final repository = KycRepositoryImpl(
          KycRemoteDataSource(api),
          ImagePickerCameraDataSource(),
        );
        final request = RequestOptions(path: '/kyc/verification');
        api.error = DioException(
          requestOptions: request,
          response: Response(
            requestOptions: request,
            statusCode: 503,
            data: {
              'error': {
                'code': 'KYC_VERIFICATION_UNAVAILABLE',
                'message': 'Identity checks are unavailable.',
              },
            },
          ),
        );
        final unavailable = await VerifyIdentity(repository)();
        expect(
          (unavailable as Failure<KycProfile>).error.code,
          'KYC_VERIFICATION_UNAVAILABLE',
        );
        api.error = DioException(
          requestOptions: request,
          type: DioExceptionType.receiveTimeout,
        );
        final disconnected = await VerifyIdentity(repository)();
        expect((disconnected as Failure<KycProfile>).error.isNetwork, isTrue);
      },
    );
  });

  group('verification operation', () {
    late _VerificationRepository repository;
    late KycCubit cubit;
    setUp(() {
      repository = _VerificationRepository();
      cubit = KycCubit(
        loadKyc: LoadKyc(repository),
        savePersonalDetails: SavePersonalDetails(repository),
        captureMedia: CaptureMedia(repository),
        uploadMedia: UploadMedia(repository),
        loadPrivateMedia: LoadPrivateMedia(repository),
        submitKyc: SubmitKyc(repository),
        resubmitKyc: ResubmitKyc(repository),
        verifyIdentity: VerifyIdentity(repository),
        recoverCapture: RecoverCapture(repository),
        discardLocalMedia: DiscardLocalMedia(repository),
      );
    });
    tearDown(() => cubit.close());

    test(
      'loading never runs cloud checks and explicit success remains editable',
      () async {
        await cubit.load();
        expect(repository.verificationCalls, 0);
        expect(await cubit.verifyIdentity(), isTrue);
        expect(repository.verificationCalls, 1);
        expect(
          cubit.state.profile!.verification!.status,
          VerificationStatus.completed,
        );
        expect(cubit.state.profile!.canEdit, isTrue);
        expect(cubit.state.profile!.canSubmit, isTrue);
        expect(await cubit.verifyIdentity(), isTrue);
        expect(repository.verificationCalls, 1);
      },
    );

    test(
      'verification excludes mutations and queues one trailing profile GET',
      () async {
        await cubit.load();
        repository.gate = Completer<Result<KycProfile>>();
        final checking = cubit.verifyIdentity();
        expect(cubit.state.busy, isTrue);
        expect(cubit.state.operation, KycOperation.verifying);
        final refreshOne = cubit.refresh();
        final refreshTwo = cubit.refresh();
        expect(await cubit.submit(), isFalse);
        expect(await cubit.capture(MediaKind.selfie), isFalse);
        expect(await cubit.verifyIdentity(), isFalse);
        expect(repository.submissionCalls, 0);
        expect(repository.captureCount, 0);
        expect(repository.loadCalls, 1);
        repository.profile = readyProfile(VerificationStatus.completed);
        repository.gate!.complete(Success(repository.profile));
        expect(await checking, isTrue);
        await Future.wait([refreshOne, refreshTwo]);
        expect(repository.loadCalls, 2);
        expect(cubit.state.busy, isFalse);
        expect(cubit.state.operation, KycOperation.none);
        expect(
          cubit.state.profile!.verification!.status,
          VerificationStatus.completed,
        );
      },
    );

    test(
      'failure preserves photos and details and allows explicit retry',
      () async {
        await cubit.load();
        repository.fail = true;
        expect(await cubit.verifyIdentity(), isFalse);
        expect(cubit.state.profile!.document!.id, 'document');
        expect(cubit.state.profile!.personalDetails!.fullName, 'Demo User');
        expect(cubit.state.error!.code, 'KYC_VERIFICATION_UNAVAILABLE');
        expect(cubit.state.errorSource, KycErrorSource.operation);
        expect(cubit.state.busy, isFalse);
        repository.fail = false;
        expect(await cubit.verifyIdentity(), isTrue);
        expect(cubit.state.error, isNull);
        expect(repository.verificationCalls, 2);
      },
    );

    test(
      'missing or pending photos and locked profiles never call the provider',
      () async {
        repository.profile = const KycProfile(
          id: 'p',
          status: KycStatus.inProgress,
          nextStep: KycStep.selfie,
        );
        await cubit.load();
        expect(await cubit.verifyIdentity(), isFalse);
        expect(cubit.state.error!.code, 'INCOMPLETE');
        repository.profile = readyProfile(
          VerificationStatus.notStarted,
          status: KycStatus.pendingReview,
        );
        await cubit.load();
        expect(await cubit.verifyIdentity(), isFalse);
        expect(cubit.state.error!.code, 'PROFILE_LOCKED');
        expect(repository.verificationCalls, 0);
      },
    );

    test(
      'disabled configuration is shown as unavailable without remote calls',
      () async {
        repository.profile = readyProfile(VerificationStatus.disabled);
        await cubit.load();
        expect(await cubit.verifyIdentity(), isFalse);
        expect(cubit.state.error!.code, 'KYC_VERIFICATION_UNAVAILABLE');
        expect(repository.verificationCalls, 0);
        expect(cubit.state.profile!.canSubmit, isTrue);
      },
    );

    test(
      'unconfirmed replacement photo blocks checking the older server photos',
      () async {
        repository.recovered = captured;
        await cubit.load();
        expect(cubit.state.pendingCaptures, isNotEmpty);
        expect(await cubit.verifyIdentity(), isFalse);
        expect(cubit.state.error!.code, 'INCOMPLETE');
        expect(repository.verificationCalls, 0);
      },
    );

    test(
      'completed evidence for different photos is not treated as cached',
      () async {
        final changed = completedJson()..['documentId'] = 'older-document';
        repository.profile = KycProfileModel.fromJson(profileJson(changed));
        await cubit.load();
        expect(await cubit.verifyIdentity(), isTrue);
        expect(repository.verificationCalls, 1);
        expect(cubit.state.profile!.verification!.documentId, 'document');
      },
    );
  });
}

Map<String, dynamic> profileJson([Map<String, dynamic>? verification]) => {
  'id': 'profile-demo',
  'status': 'in_progress',
  'nextStep': 'review',
  'personalDetails': {
    'fullName': 'Demo User',
    'dateOfBirth': '1995-04-15',
    'nationality': 'Vietnamese',
    'address': '1 Demo Street',
    'documentNumber': 'DEMO1234',
  },
  'document': {
    'id': 'document',
    'mimeType': 'image/jpeg',
    'size': 100,
    'documentType': 'passport',
  },
  'selfie': {'id': 'selfie', 'mimeType': 'image/jpeg', 'size': 100},
  'verification': ?verification,
};

Map<String, dynamic> completedJson() => {
  'provider': 'aws',
  'status': 'completed',
  'documentId': 'document',
  'selfieId': 'selfie',
  'checkedAt': '2026-10-11T00:00:00.000Z',
  'ocr': {
    'status': 'succeeded',
    'text': 'NAME DEMO USER',
    'fields': {
      'fullName': 'DEMO USER',
      'dateOfBirth': '1995-04-15',
      'documentNumber': 'DEMO1234',
    },
    'confidence': 98.5,
  },
  'faceMatch': {'status': 'matched', 'similarity': 97, 'threshold': 90},
};

KycProfile readyProfile(
  VerificationStatus checks, {
  KycStatus status = KycStatus.inProgress,
}) => KycProfile(
  id: 'profile-demo',
  status: status,
  nextStep: KycStep.review,
  personalDetails: const PersonalDetails(
    fullName: 'Demo User',
    dateOfBirth: '1995-04-15',
    nationality: 'Vietnamese',
    address: '1 Demo Street',
    documentNumber: 'DEMO1234',
  ),
  document: const KycMedia(id: 'document', mimeType: 'image/jpeg', size: 100),
  selfie: const KycMedia(id: 'selfie', mimeType: 'image/jpeg', size: 100),
  verification: KycVerification(
    provider: checks == VerificationStatus.disabled ? 'none' : 'aws',
    status: checks,
    documentId: 'document',
    selfieId: 'selfie',
  ),
);

class _VerificationApi extends ApiClient {
  _VerificationApi() : super(Dio());
  final paths = <String>[];
  Map<String, dynamic> response = {};
  Map<String, dynamic>? body;
  Object? error;
  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    paths.add(path);
    body = data;
    if (error != null) throw error!;
    return response;
  }
}

class _VerificationRepository extends FakeKycRepository {
  _VerificationRepository() {
    profile = readyProfile(VerificationStatus.notStarted);
  }
  int verificationCalls = 0;
  int loadCalls = 0;
  int submissionCalls = 0;
  bool fail = false;
  Completer<Result<KycProfile>>? gate;
  @override
  Future<Result<KycProfile>> load() {
    loadCalls++;
    return super.load();
  }

  @override
  Future<Result<KycProfile>> submit() {
    submissionCalls++;
    return super.submit();
  }

  @override
  Future<Result<KycProfile>> verifyIdentity() async {
    verificationCalls++;
    if (gate != null) return gate!.future;
    if (fail) {
      return const Failure(
        AppFailure(
          code: 'KYC_VERIFICATION_UNAVAILABLE',
          message: 'Identity checks unavailable. Try again.',
        ),
      );
    }
    profile = readyProfile(VerificationStatus.completed);
    return Success(profile);
  }
}
