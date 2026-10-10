import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/core/domain/result.dart';
import 'package:kyc_onboarding/core/network/api_client.dart';
import 'package:kyc_onboarding/features/kyc/data/datasources/camera_datasource.dart';
import 'package:kyc_onboarding/features/kyc/data/datasources/kyc_remote_datasource.dart';
import 'package:kyc_onboarding/features/kyc/data/repositories/kyc_repository_impl.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';

void main() {
  test(
    'acknowledged capture is removed when app restart follows a successful server upload',
    () async {
      final camera = RecoveryCamera();
      final repository = KycRepositoryImpl(
        KycRemoteDataSource(ApiClient(Dio())),
        camera,
      );
      final result = await repository.recover(
        MediaKind.document,
        'demo-profile',
        confirmedCaptureId: 'new-capture',
      );
      expect((result as Success<CapturedMedia?>).value, isNull);
      expect(camera.removed, isTrue);
    },
  );
  test(
    'failed replacement capture is preserved despite an earlier uploaded image',
    () async {
      final camera = RecoveryCamera();
      final repository = KycRepositoryImpl(
        KycRemoteDataSource(ApiClient(Dio())),
        camera,
      );
      final result = await repository.recover(
        MediaKind.document,
        'demo-profile',
        confirmedCaptureId: 'old-capture',
      );
      expect(
        (result as Success<CapturedMedia?>).value!.captureId,
        'new-capture',
      );
      expect(camera.removed, isFalse);
    },
  );
}

class RecoveryCamera implements CameraDataSource {
  bool removed = false;
  @override
  Future<CapturedMedia?> recover(MediaKind kind, String profileId) async =>
      CapturedMedia(
        kind: kind,
        filePath: '/private/demo.png',
        bytes: Uint8List(0),
        documentType: DocumentType.passport,
        captureId: 'new-capture',
      );
  @override
  Future<CapturedMedia?> capture(
    MediaKind kind,
    String profileId, {
    DocumentType? documentType,
  }) async =>
      null;
  @override
  Future<void> remove(CapturedMedia media) async {
    removed = true;
  }

  @override
  Future<void> discard(String profileId) async {}
}
