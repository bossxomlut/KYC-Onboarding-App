import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:kyc_onboarding/features/kyc/data/datasources/camera_capture_exception.dart';
import 'package:kyc_onboarding/features/kyc/data/datasources/camera_photo_cropper.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/camera_capture_crop.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';

void main() {
  const cropper = CameraPhotoCropper();

  for (final orientation in [1, 6, 8]) {
    test(
      'selfie mirrored guide crops upright source pixels with EXIF $orientation',
      () async {
        final upright = image.Image(width: 800, height: 1200);
        image.fill(upright, color: image.ColorRgb8(200, 20, 200));
        image.fillRect(
          upright,
          x1: 500,
          y1: 200,
          x2: 699,
          y2: 469,
          color: image.ColorRgb8(20, 200, 40),
        );
        image.fillRect(
          upright,
          x1: 520,
          y1: 220,
          x2: 549,
          y2: 249,
          color: image.ColorRgb8(20, 40, 220),
        );
        final stored = image.copyRotate(
          upright,
          angle: switch (orientation) {
            6 => -90,
            8 => 90,
            _ => 0,
          },
        )..exif.imageIfd.orientation = orientation;
        final selfieCrop = CameraCaptureCrop.fromViewport(
          viewportWidth: 400,
          viewportHeight: 600,
          frameLeft: 50,
          frameTop: 100,
          frameWidth: 100,
          frameHeight: 135,
          previewAspectRatio: 2 / 3,
          marginFraction: 0,
          isPreviewMirrored: true,
        );
        final result = image.decodeJpg(
          await cropper.crop(
            image.encodeJpg(stored, quality: 100),
            selfieCrop,
            kind: MediaKind.selfie,
          ),
        )!;
        expect((result.width, result.height), (200, 270));
        expect(result.exif.imageIfd.orientation, isNull);
        _expectRgb(result.getPixel(30, 30), (20, 40, 220));
        _expectRgb(result.getPixel(170, 240), (20, 200, 40));
      },
    );
  }

  test(
    'corrupt selfie returns a selfie crop error without full-image fallback',
    () async {
      await expectLater(
        cropper.crop(
          Uint8List.fromList([1, 2, 3]),
          _crop(),
          kind: MediaKind.selfie,
        ),
        throwsA(
          isA<CameraCaptureException>().having(
            (error) => error.code,
            'code',
            'SELFIE_CROP_FAILED',
          ),
        ),
      );
    },
  );

  test(
    'encodes only the rectangular guide region at source resolution',
    () async {
      final source = _coloredDocument(width: 800, height: 1200);
      final crop = _crop(marginFraction: 0);

      final bytes = await cropper.crop(
        image.encodeJpg(source, quality: 100),
        crop,
      );
      final result = image.decodeJpg(bytes)!;

      expect(bytes.take(2), [0xff, 0xd8]);
      expect((result.width, result.height), (400, 200));
      _expectRgb(result.getPixel(15, 15), (20, 200, 40));
      _expectRgb(result.getPixel(385, 185), (20, 200, 40));
      expect(
        result.width * result.height,
        lessThan(source.width * source.height),
      );
    },
  );

  test('keeps only a three percent safety margin outside the guide', () async {
    final source = _coloredDocument(width: 800, height: 1200);
    final bytes = await cropper.crop(image.encodePng(source), _crop());
    final result = image.decodeJpg(bytes)!;

    expect((result.width, result.height), (424, 212));
    _expectRgb(result.getPixel(4, 4), (200, 20, 200));
    _expectRgb(result.getPixel(24, 24), (20, 200, 40));
    _expectRgb(result.getPixel(400, 185), (20, 200, 40));
  });

  test(
    'maps the guide into the visible part of a different photo aspect',
    () async {
      final source = image.Image(width: 800, height: 1200);
      image.fill(source, color: image.ColorRgb8(200, 20, 200));
      image.fillRect(
        source,
        x1: 197,
        y1: 375,
        x2: 602,
        y2: 628,
        color: image.ColorRgb8(20, 200, 40),
      );
      image.fillRect(
        source,
        x1: 205,
        y1: 385,
        x2: 245,
        y2: 420,
        color: image.ColorRgb8(20, 40, 220),
      );
      final crop = CameraCaptureCrop.fromViewport(
        viewportWidth: 360,
        viewportHeight: 640,
        frameLeft: 72,
        frameTop: 200,
        frameWidth: 216,
        frameHeight: 135,
        previewAspectRatio: 9 / 16,
        marginFraction: 0,
      );

      final result = image.decodeJpg(
        await cropper.crop(image.encodePng(source), crop),
      )!;

      expect((result.width, result.height), (406, 254));
      _expectRgb(result.getPixel(20, 20), (20, 40, 220));
      _expectRgb(result.getPixel(380, 230), (20, 200, 40));
    },
  );

  for (final orientation in [3, 6, 8]) {
    test('bakes JPEG EXIF orientation $orientation before cropping', () async {
      final upright = _coloredDocument(width: 800, height: 1200);
      image.fillRect(
        upright,
        x1: 220,
        y1: 420,
        x2: 280,
        y2: 480,
        color: image.ColorRgb8(20, 40, 220),
      );
      final stored = image.copyRotate(
        upright,
        angle: switch (orientation) {
          3 => 180,
          6 => -90,
          _ => 90,
        },
      )..exif.imageIfd.orientation = orientation;

      final result = image.decodeJpg(
        await cropper.crop(
          image.encodeJpg(stored, quality: 100),
          _crop(marginFraction: 0),
        ),
      )!;

      expect((result.width, result.height), (400, 200));
      expect(result.exif.imageIfd.orientation, isNull);
      _expectRgb(result.getPixel(40, 40), (20, 40, 220));
      _expectRgb(result.getPixel(370, 170), (20, 200, 40));
    });
  }

  test(
    'preserves original pixels and sharp document strokes without resizing',
    () async {
      final source = image.Image(width: 1600, height: 1200);
      for (final pixel in source) {
        final channel = pixel.x % 8 < 4 ? 0 : 255;
        pixel.setRgb(channel, channel, channel);
      }
      final crop = CameraCaptureCrop.fromViewport(
        viewportWidth: 400,
        viewportHeight: 300,
        frameLeft: 100,
        frameTop: 100,
        frameWidth: 200,
        frameHeight: 100,
        previewAspectRatio: 4 / 3,
        marginFraction: 0,
      );

      final result = image.decodeJpg(
        await cropper.crop(image.encodeJpg(source, quality: 100), crop),
      )!;

      expect((result.width, result.height), (800, 400));
      expect(result.getPixel(81, 100).r, lessThan(10));
      expect(result.getPixel(85, 100).r, greaterThan(245));
    },
  );

  for (final source in [
    Uint8List(0),
    Uint8List.fromList([1, 2, 3]),
    Uint8List.fromList([0xff, 0xd8, 0xff, 0xe1, 0, 40, 1]),
  ]) {
    test(
      'rejects corrupt photo bytes instead of saving a full image',
      () async {
        await expectLater(
          cropper.crop(source, _crop()),
          throwsA(
            isA<CameraCaptureException>().having(
              (error) => error.code,
              'code',
              'DOCUMENT_CROP_FAILED',
            ),
          ),
        );
      },
    );
  }
}

CameraCaptureCrop _crop({double marginFraction = .03}) {
  return CameraCaptureCrop.fromViewport(
    viewportWidth: 400,
    viewportHeight: 600,
    frameLeft: 100,
    frameTop: 200,
    frameWidth: 200,
    frameHeight: 100,
    previewAspectRatio: 2 / 3,
    marginFraction: marginFraction,
  );
}

image.Image _coloredDocument({required int width, required int height}) {
  final source = image.Image(width: width, height: height);
  image.fill(source, color: image.ColorRgb8(200, 20, 200));
  image.fillRect(
    source,
    x1: width ~/ 4,
    y1: height ~/ 3,
    x2: width * 3 ~/ 4 - 1,
    y2: height ~/ 2 - 1,
    color: image.ColorRgb8(20, 200, 40),
  );
  return source;
}

void _expectRgb(image.Pixel actual, (int, int, int) expected) {
  expect(actual.r, closeTo(expected.$1, 5));
  expect(actual.g, closeTo(expected.$2, 5));
  expect(actual.b, closeTo(expected.$3, 5));
}
