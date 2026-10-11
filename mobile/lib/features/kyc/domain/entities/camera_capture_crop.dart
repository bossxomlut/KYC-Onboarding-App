import 'dart:math' as math;

/// The capture guide in normalized coordinates of the upright camera preview.
///
/// Preview placement uses a centered cover fit. A still image with a different
/// aspect ratio is treated as the full sensor image surrounding that preview.
class CameraCaptureCrop {
  const CameraCaptureCrop._({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.previewAspectRatio,
    required this.marginFraction,
    required this.isPreviewMirrored,
  });

  factory CameraCaptureCrop.fromViewport({
    required double viewportWidth,
    required double viewportHeight,
    required double frameLeft,
    required double frameTop,
    required double frameWidth,
    required double frameHeight,
    required double previewAspectRatio,
    double marginFraction = .03,
    bool isPreviewMirrored = false,
  }) {
    _requirePositiveFinite('viewportWidth', viewportWidth);
    _requirePositiveFinite('viewportHeight', viewportHeight);
    _requirePositiveFinite('frameWidth', frameWidth);
    _requirePositiveFinite('frameHeight', frameHeight);
    _requirePositiveFinite('previewAspectRatio', previewAspectRatio);
    _requireNonnegativeFinite('frameLeft', frameLeft);
    _requireNonnegativeFinite('frameTop', frameTop);
    _requireNonnegativeFinite('marginFraction', marginFraction);
    if (frameLeft + frameWidth > viewportWidth ||
        frameTop + frameHeight > viewportHeight) {
      throw ArgumentError('Capture frame must be inside the preview viewport.');
    }

    final displayWidth = math.max(
      viewportWidth,
      viewportHeight * previewAspectRatio,
    );
    final displayHeight = displayWidth / previewAspectRatio;
    _requirePositiveFinite('displayWidth', displayWidth);
    _requirePositiveFinite('displayHeight', displayHeight);
    final left =
        (frameLeft + (displayWidth - viewportWidth) / 2) / displayWidth;
    final top =
        (frameTop + (displayHeight - viewportHeight) / 2) / displayHeight;
    final width = frameWidth / displayWidth;
    final height = frameHeight / displayHeight;
    _requireNonnegativeFinite('normalized left', left);
    _requireNonnegativeFinite('normalized top', top);
    _requirePositiveFinite('normalized width', width);
    _requirePositiveFinite('normalized height', height);

    return CameraCaptureCrop._(
      left: left,
      top: top,
      width: width,
      height: height,
      previewAspectRatio: previewAspectRatio,
      marginFraction: marginFraction,
      isPreviewMirrored: isPreviewMirrored,
    );
  }

  final double left;
  final double top;
  final double width;
  final double height;
  final double previewAspectRatio;

  /// Fraction of the guide width/height kept outside each corresponding edge.
  final double marginFraction;

  /// Front preview is mirrored; the saved photo keeps the sensor orientation.
  final bool isPreviewMirrored;

  double get right => left + width;
  double get bottom => top + height;

  /// Maps the guide to a decoded still image after its orientation is applied.
  PixelCropBounds boundsForImage({required int width, required int height}) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Still image dimensions must be positive.');
    }
    final imageWidth = width.toDouble();
    final imageHeight = height.toDouble();
    final imageAspectRatio = imageWidth / imageHeight;
    final previewWidth = imageAspectRatio > previewAspectRatio
        ? imageHeight * previewAspectRatio
        : imageWidth;
    final previewHeight = imageAspectRatio > previewAspectRatio
        ? imageHeight
        : imageWidth / previewAspectRatio;
    _requirePositiveFinite('preview width in image', previewWidth);
    _requirePositiveFinite('preview height in image', previewHeight);
    final offsetLeft = (imageWidth - previewWidth) / 2;
    final offsetTop = (imageHeight - previewHeight) / 2;
    final frameWidth = this.width * previewWidth;
    final frameHeight = this.height * previewHeight;
    final marginWidth = frameWidth * marginFraction;
    final marginHeight = frameHeight * marginFraction;
    final sourceLeft = isPreviewMirrored ? 1 - right : left;
    final sourceRight = isPreviewMirrored ? 1 - left : right;
    final cropLeft = offsetLeft + sourceLeft * previewWidth - marginWidth;
    final cropTop = offsetTop + top * previewHeight - marginHeight;
    final cropRight = offsetLeft + sourceRight * previewWidth + marginWidth;
    final cropBottom = offsetTop + bottom * previewHeight + marginHeight;
    if (![cropLeft, cropTop, cropRight, cropBottom].every((v) => v.isFinite)) {
      throw ArgumentError('Capture crop cannot be mapped to the still image.');
    }

    final pixelLeft = cropLeft.clamp(0, imageWidth).floor();
    final pixelTop = cropTop.clamp(0, imageHeight).floor();
    final pixelRight = cropRight.clamp(0, imageWidth).ceil();
    final pixelBottom = cropBottom.clamp(0, imageHeight).ceil();
    if (pixelRight <= pixelLeft || pixelBottom <= pixelTop) {
      throw ArgumentError('Capture crop must contain image pixels.');
    }
    return PixelCropBounds(
      left: pixelLeft,
      top: pixelTop,
      width: pixelRight - pixelLeft,
      height: pixelBottom - pixelTop,
    );
  }

  static void _requirePositiveFinite(String name, double value) {
    if (!value.isFinite || value <= 0) {
      throw ArgumentError.value(value, name, 'Must be finite and positive.');
    }
  }

  static void _requireNonnegativeFinite(String name, double value) {
    if (!value.isFinite || value < 0) {
      throw ArgumentError.value(value, name, 'Must be finite and nonnegative.');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is CameraCaptureCrop &&
      left == other.left &&
      top == other.top &&
      width == other.width &&
      height == other.height &&
      previewAspectRatio == other.previewAspectRatio &&
      marginFraction == other.marginFraction &&
      isPreviewMirrored == other.isPreviewMirrored;

  @override
  int get hashCode => Object.hash(
    left,
    top,
    width,
    height,
    previewAspectRatio,
    marginFraction,
    isPreviewMirrored,
  );
}

/// A nonempty rectangle in upright still-image pixels.
class PixelCropBounds {
  const PixelCropBounds({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  }) : assert(left >= 0),
       assert(top >= 0),
       assert(width > 0),
       assert(height > 0);

  final int left;
  final int top;
  final int width;
  final int height;

  int get right => left + width;
  int get bottom => top + height;

  @override
  bool operator ==(Object other) =>
      other is PixelCropBounds &&
      left == other.left &&
      top == other.top &&
      width == other.width &&
      height == other.height;

  @override
  int get hashCode => Object.hash(left, top, width, height);
}
