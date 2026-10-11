import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as image;

import '../../domain/entities/document_capture_crop.dart';
import 'camera_capture_exception.dart';

/// Crops original camera pixels before private persistence or upload.
class DocumentPhotoCropper {
  const DocumentPhotoCropper();

  Future<Uint8List> crop(Uint8List source, DocumentCaptureCrop crop) async {
    try {
      return await compute(
        _cropDocumentPhoto,
        _DocumentCropRequest(source, crop),
        debugLabel: 'document_photo_crop',
      );
    } catch (_) {
      throw const CameraCaptureException(
        'DOCUMENT_CROP_FAILED',
        'The document photo could not be prepared. Please take it again.',
      );
    }
  }
}

class _DocumentCropRequest {
  const _DocumentCropRequest(this.source, this.crop);

  final Uint8List source;
  final DocumentCaptureCrop crop;
}

Uint8List _cropDocumentPhoto(_DocumentCropRequest request) {
  final decoded = image.decodeImage(request.source);
  if (decoded == null) {
    throw const FormatException('Document photo could not be decoded');
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
