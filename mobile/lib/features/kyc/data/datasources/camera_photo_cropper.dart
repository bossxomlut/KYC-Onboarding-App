import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as image;

import '../../domain/entities/camera_capture_crop.dart';
import '../../domain/entities/kyc_profile.dart';
import 'camera_capture_exception.dart';

/// Crops original camera pixels before private persistence or upload.
class CameraPhotoCropper {
  const CameraPhotoCropper();

  Future<Uint8List> crop(
    Uint8List source,
    CameraCaptureCrop crop, {
    MediaKind kind = MediaKind.document,
  }) async {
    try {
      return await compute(
        _cropCameraPhoto,
        _PhotoCropRequest(source, crop),
        debugLabel: 'camera_photo_crop',
      );
    } catch (_) {
      throw CameraCaptureException(
        kind == MediaKind.document
            ? 'DOCUMENT_CROP_FAILED'
            : 'SELFIE_CROP_FAILED',
        'The ${kind == MediaKind.document ? 'document photo' : 'selfie'} could not be prepared. Please take it again.',
      );
    }
  }
}

class _PhotoCropRequest {
  const _PhotoCropRequest(this.source, this.crop);

  final Uint8List source;
  final CameraCaptureCrop crop;
}

Uint8List _cropCameraPhoto(_PhotoCropRequest request) {
  final decoded = image.decodeImage(request.source);
  if (decoded == null) {
    throw const FormatException('Camera photo could not be decoded');
  }
  // Some decoders bake EXIF automatically; this also covers formats that do not.
  final upright = image.bakeOrientation(decoded);
  final bounds = request.crop.boundsForImage(
    width: upright.width,
    height: upright.height,
  );
  final cropped = image.copyCrop(
    upright,
    x: bounds.left,
    y: bounds.top,
    width: bounds.width,
    height: bounds.height,
  );
  // Source metadata can contain stale dimensions, rotation, or location.
  cropped.exif = image.ExifData();
  return image.encodeJpg(cropped, quality: 95);
}
