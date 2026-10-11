import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:kyc_onboarding/features/kyc/data/datasources/camera_datasource.dart';
import 'package:kyc_onboarding/features/kyc/data/datasources/in_app_camera_driver.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/document_capture_crop.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';

void main() {
  late Directory temporary;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('document_crop_test_');
  });
  tearDown(() async => temporary.delete(recursive: true));

  final crop = DocumentCaptureCrop.fromViewport(
    viewportWidth: 300,
    viewportHeight: 400,
    frameLeft: 30,
    frameTop: 100,
    frameWidth: 240,
    frameHeight: 150,
    previewAspectRatio: .75,
  );

  test(
    'document persists and recovers only the framed region with a small border',
    () async {
      final photo = image.Image(width: 300, height: 400);
      image.fill(photo, color: image.ColorRgb8(20, 20, 220));
      image.fillRect(
        photo,
        x1: 30,
        y1: 100,
        x2: 269,
        y2: 249,
        color: image.ColorRgb8(220, 20, 20),
      );
      final original = File('${temporary.path}/raw.jpg');
      await original.writeAsBytes(image.encodeJpg(photo, quality: 100));
      final driver = _PhotoDriver(original.path);
      final source = InAppCameraDataSource(
        driver: driver,
        directory: () async => temporary,
        isAndroid: false,
      );

      final captured = (await source.capture(
        MediaKind.document,
        'crop-profile',
        documentType: DocumentType.nationalId,
        crop: crop,
      ))!;
      final decoded = image.decodeJpg(captured.bytes)!;
      final expected = crop.boundsForImage(width: 300, height: 400);
      expect(decoded.width, expected.width);
      expect(decoded.height, expected.height);
      expect(decoded.width, lessThan(photo.width));
      expect(decoded.height, lessThan(photo.height));
      expect(
        decoded.getPixel(decoded.width ~/ 2, decoded.height ~/ 2).r,
        greaterThan(180),
      );
      expect(decoded.getPixel(1, 1).b, greaterThan(180));
      expect(await original.exists(), isFalse);
      expect(await File(captured.filePath).readAsBytes(), captured.bytes);
      final recovered = (await source.recover(
        MediaKind.document,
        'crop-profile',
      ))!;
      expect(recovered.bytes, captured.bytes);
      expect(recovered.captureId, captured.captureId);
      expect(recovered.documentType, DocumentType.nationalId);
    },
  );

  test(
    'document without frame geometry cannot save an uncropped image',
    () async {
      final driver = _PhotoDriver('${temporary.path}/raw.jpg');
      final source = InAppCameraDataSource(
        driver: driver,
        directory: () async => temporary,
      );
      await expectLater(
        source.capture(MediaKind.document, 'crop-profile'),
        throwsA(
          isA<CameraCaptureException>().having(
            (error) => error.code,
            'code',
            'DOCUMENT_CROP_REQUIRED',
          ),
        ),
      );
      expect(driver.pictures, 0);
    },
  );

  test('selfie keeps its original bytes and dimensions', () async {
    final photo = image.Image(width: 300, height: 400);
    final originalBytes = image.encodeJpg(photo);
    final original = File('${temporary.path}/selfie.jpg');
    await original.writeAsBytes(originalBytes);
    final source = InAppCameraDataSource(
      driver: _PhotoDriver(original.path),
      directory: () async => temporary,
      isAndroid: false,
    );
    final captured = (await source.capture(
      MediaKind.selfie,
      'crop-profile',
      crop: crop,
    ))!;
    expect(captured.bytes, originalBytes);
    expect(image.decodeJpg(captured.bytes)!.width, 300);
    expect(image.decodeJpg(captured.bytes)!.height, 400);
  });

  test(
    'crop failure cleans raw capture and preserves the previous pending document',
    () async {
      final folder = await Directory(
        '${temporary.path}/kyc_captures/crop-profile',
      ).create(recursive: true);
      final existing = File(
        '${folder.path}/document_national_id_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.jpg',
      );
      await existing.writeAsBytes([1, 2, 3]);
      final original = File('${temporary.path}/corrupt.jpg');
      await original.writeAsBytes([4, 5, 6]);
      final source = InAppCameraDataSource(
        driver: _PhotoDriver(original.path),
        directory: () async => temporary,
        isAndroid: false,
      );
      await expectLater(
        source.capture(MediaKind.document, 'crop-profile', crop: crop),
        throwsA(
          isA<CameraCaptureException>().having(
            (error) => error.code,
            'code',
            'DOCUMENT_CROP_FAILED',
          ),
        ),
      );
      expect(await original.exists(), isFalse);
      expect(await existing.readAsBytes(), [1, 2, 3]);
    },
  );
}

class _PhotoDriver extends InAppCameraDriver {
  _PhotoDriver(this.path);
  final String path;
  int pictures = 0;
  @override
  Future<XFile> takePicture(MediaKind kind) async {
    pictures++;
    return XFile(path);
  }
}
