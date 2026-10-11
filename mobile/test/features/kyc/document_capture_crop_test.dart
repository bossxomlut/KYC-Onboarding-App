import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/camera_capture_crop.dart';

CameraCaptureCrop crop({
  double viewportWidth = 390,
  double viewportHeight = 844,
  double frameLeft = 35,
  double frameTop = 250,
  double frameWidth = 320,
  double frameHeight = 200,
  double previewAspectRatio = .75,
  double marginFraction = .03,
  bool isPreviewMirrored = false,
}) => CameraCaptureCrop.fromViewport(
  viewportWidth: viewportWidth,
  viewportHeight: viewportHeight,
  frameLeft: frameLeft,
  frameTop: frameTop,
  frameWidth: frameWidth,
  frameHeight: frameHeight,
  previewAspectRatio: previewAspectRatio,
  marginFraction: marginFraction,
  isPreviewMirrored: isPreviewMirrored,
);

void expectBounds(
  PixelCropBounds bounds, {
  required int left,
  required int top,
  required int right,
  required int bottom,
}) {
  expect(bounds.left, left);
  expect(bounds.top, top);
  expect(bounds.right, right);
  expect(bounds.bottom, bottom);
  expect(bounds.width, right - left);
  expect(bounds.height, bottom - top);
}

void main() {
  test(
    'mirrored front guide selects the opposite raw region without flipping pixels',
    () {
      final selfie = crop(
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
      expect(selfie.left, .125);
      expectBounds(
        selfie.boundsForImage(width: 800, height: 1200),
        left: 500,
        top: 200,
        right: 700,
        bottom: 470,
      );
    },
  );

  test(
    'mirrored front margin maps into a different still aspect and clamps at edges',
    () {
      final selfie = crop(
        viewportWidth: 400,
        viewportHeight: 600,
        frameLeft: 50,
        frameTop: 100,
        frameWidth: 100,
        frameHeight: 135,
        previewAspectRatio: 2 / 3,
        isPreviewMirrored: true,
      );
      expectBounds(
        selfie.boundsForImage(width: 1200, height: 1200),
        left: 694,
        top: 191,
        right: 906,
        bottom: 479,
      );
      final edge = crop(
        viewportWidth: 1000,
        viewportHeight: 1000,
        frameLeft: 0,
        frameTop: 20,
        frameWidth: 100,
        frameHeight: 200,
        previewAspectRatio: 1,
        isPreviewMirrored: true,
      );
      expectBounds(
        edge.boundsForImage(width: 1000, height: 1000),
        left: 897,
        top: 14,
        right: 1000,
        bottom: 226,
      );
    },
  );

  test('mirror metadata is part of capture crop equality', () {
    final normal = crop();
    final mirrored = crop(isPreviewMirrored: true);
    expect(normal, crop());
    expect(normal.hashCode, crop().hashCode);
    expect(mirrored, isNot(normal));
    expect(mirrored, crop(isPreviewMirrored: true));
  });

  test('portrait cover maps the offset frame instead of image centre', () {
    final document = crop(marginFraction: 0);

    // A 3:4 preview covers 390 x 844 with 121.5 points off each side.
    expect(document.left, closeTo(156.5 / 633, 1e-12));
    expect(document.top, closeTo(250 / 844, 1e-12));
    expect(document.width, closeTo(320 / 633, 1e-12));
    expect(document.height, closeTo(200 / 844, 1e-12));
    expectBounds(
      document.boundsForImage(width: 3000, height: 4000),
      left: 741,
      top: 1184,
      right: 2259,
      bottom: 2133,
    );
  });

  test('default margin preserves three percent outside every frame edge', () {
    final document = crop();
    expect(document.marginFraction, .03);
    expectBounds(
      document.boundsForImage(width: 3000, height: 4000),
      left: 696,
      top: 1156,
      right: 2304,
      bottom: 2162,
    );
  });

  test('wide viewport maps a frame offset by the side controls', () {
    final document = crop(
      viewportWidth: 844,
      viewportHeight: 390,
      frameLeft: 60,
      frameTop: 110,
      frameWidth: 400,
      frameHeight: 200,
      marginFraction: 0,
    );
    expectBounds(
      document.boundsForImage(width: 3000, height: 4000),
      left: 213,
      top: 1697,
      right: 1636,
      bottom: 2409,
    );
  });

  test('16:9 portrait preview maps into a wider still sensor image', () {
    final document = crop(
      viewportWidth: 900,
      viewportHeight: 1600,
      frameLeft: 180,
      frameTop: 400,
      frameWidth: 540,
      frameHeight: 340,
      previewAspectRatio: 9 / 16,
      marginFraction: 0,
    );

    // Preview excludes 375 pixels from both sides of the 3000 x 4000 still.
    expectBounds(
      document.boundsForImage(width: 3000, height: 4000),
      left: 825,
      top: 1000,
      right: 2175,
      bottom: 1850,
    );
  });

  test('3:4 portrait preview maps into a taller still sensor image', () {
    final document = crop(
      viewportWidth: 750,
      viewportHeight: 1000,
      frameLeft: 150,
      frameTop: 250,
      frameWidth: 450,
      frameHeight: 250,
      marginFraction: 0,
    );

    // Preview excludes 667 pixels from the top and bottom of the still.
    expectBounds(
      document.boundsForImage(width: 3000, height: 5334),
      left: 600,
      top: 1667,
      right: 2400,
      bottom: 2667,
    );
  });

  test('card and passport retain the aspect of their own frame', () {
    for (final aspect in [1.586, 1.42]) {
      final frameWidth = 200 * aspect;
      final document = crop(
        viewportWidth: 1000,
        viewportHeight: 1000,
        frameLeft: 100,
        frameTop: 200,
        frameWidth: frameWidth,
        frameHeight: 200,
        previewAspectRatio: 1,
        marginFraction: 0,
      );
      final bounds = document.boundsForImage(width: 10000, height: 10000);
      expect(bounds.left, 1000);
      expect(bounds.top, 2000);
      expect(bounds.width, closeTo(frameWidth * 10, 1));
      expect(bounds.height, 2000);
      expect(bounds.width / bounds.height, closeTo(aspect, .001));
    }
  });

  test('margin clamps at every image boundary', () {
    final nearTopLeft = crop(
      viewportWidth: 1000,
      viewportHeight: 1000,
      frameLeft: 0,
      frameTop: 20,
      frameWidth: 100,
      frameHeight: 200,
      previewAspectRatio: 1,
    );
    expectBounds(
      nearTopLeft.boundsForImage(width: 1000, height: 1000),
      left: 0,
      top: 14,
      right: 103,
      bottom: 226,
    );
    final nearBottomRight = crop(
      viewportWidth: 1000,
      viewportHeight: 1000,
      frameLeft: 900,
      frameTop: 800,
      frameWidth: 100,
      frameHeight: 200,
      previewAspectRatio: 1,
    );
    expectBounds(
      nearBottomRight.boundsForImage(width: 1000, height: 1000),
      left: 897,
      top: 794,
      right: 1000,
      bottom: 1000,
    );
  });

  test('subpixel frame rounds out to a nonempty image region', () {
    final document = crop(
      viewportWidth: 100,
      viewportHeight: 100,
      frameLeft: 99.9,
      frameTop: 99.9,
      frameWidth: .1,
      frameHeight: .1,
      previewAspectRatio: 1,
      marginFraction: 0,
    );
    expectBounds(
      document.boundsForImage(width: 10, height: 10),
      left: 9,
      top: 9,
      right: 10,
      bottom: 10,
    );
  });

  test(
    'invalid viewport, ratio or frame never falls back to the full image',
    () {
      for (final invalid in [0.0, -1.0, double.nan, double.infinity]) {
        expect(() => crop(viewportWidth: invalid), throwsArgumentError);
        expect(() => crop(viewportHeight: invalid), throwsArgumentError);
        expect(() => crop(frameWidth: invalid), throwsArgumentError);
        expect(() => crop(frameHeight: invalid), throwsArgumentError);
        expect(() => crop(previewAspectRatio: invalid), throwsArgumentError);
      }
      for (final invalid in [-1.0, double.nan, double.infinity]) {
        expect(() => crop(frameLeft: invalid), throwsArgumentError);
        expect(() => crop(frameTop: invalid), throwsArgumentError);
        expect(() => crop(marginFraction: invalid), throwsArgumentError);
      }
      expect(() => crop(frameLeft: 71), throwsArgumentError);
      expect(() => crop(frameTop: 645), throwsArgumentError);
      expect(
        () => crop(viewportWidth: 1e308, previewAspectRatio: 1e-308),
        throwsArgumentError,
      );
    },
  );

  test('invalid still dimensions fail before producing pixel bounds', () {
    final document = crop();
    for (final invalid in [0, -1]) {
      expect(
        () => document.boundsForImage(width: invalid, height: 4000),
        throwsArgumentError,
      );
      expect(
        () => document.boundsForImage(width: 3000, height: invalid),
        throwsArgumentError,
      );
    }
  });
}
