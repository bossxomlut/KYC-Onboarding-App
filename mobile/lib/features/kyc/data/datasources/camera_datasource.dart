import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/entities/kyc_profile.dart';

/// The only boundary that knows the camera plugin and private temporary files.
abstract interface class CameraDataSource {
  Future<CapturedMedia?> capture(
    MediaKind kind,
    String profileId, {
    DocumentType? documentType,
  });
  Future<CapturedMedia?> recover(MediaKind kind, String profileId);
  Future<void> remove(CapturedMedia media);
  Future<void> discard(String profileId);
}

class CameraCaptureException implements Exception {
  const CameraCaptureException(this.code, this.message);
  final String code;
  final String message;
}

class ImagePickerCameraDataSource implements CameraDataSource {
  ImagePickerCameraDataSource({
    ImagePicker? picker,
    Future<Directory> Function()? directory,
    bool? isAndroid,
  })  : _picker = picker ?? ImagePicker(),
        _directory = directory ?? getTemporaryDirectory,
        _isAndroid = isAndroid ?? Platform.isAndroid;
  final ImagePicker _picker;
  final Future<Directory> Function() _directory;
  final bool _isAndroid;
  String _newCaptureId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<Directory> _profileDirectory(String profileId) async {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(profileId)) {
      throw const FormatException('Invalid profile ID');
    }
    final directory = Directory(
      '${(await _directory()).path}/kyc_captures/$profileId',
    );
    return directory.create(recursive: true);
  }

  @override
  Future<CapturedMedia?> capture(
    MediaKind kind,
    String profileId, {
    DocumentType? documentType,
  }) async {
    final directory = await _profileDirectory(profileId);
    final intent = File('${directory.path}/capture_intent.json');
    final captureId = _newCaptureId();
    await intent.writeAsString(
      jsonEncode({
        'kind': kind.name,
        'documentType': documentType?.apiValue,
        'captureId': captureId,
      }),
      flush: true,
    );
    try {
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice:
            kind == MediaKind.selfie ? CameraDevice.front : CameraDevice.rear,
        maxWidth: 1800,
        maxHeight: 1800,
        imageQuality: 85,
      );
      if (file == null) {
        await intent.delete();
        return null;
      }
      return await _persist(file, kind, profileId, documentType, captureId);
    } on PlatformException catch (error) {
      if (await intent.exists()) await intent.delete();
      if (error.code.toLowerCase().contains('access') ||
          error.code.toLowerCase().contains('permission')) {
        throw const CameraCaptureException(
          'CAMERA_PERMISSION',
          'Allow camera access in your device Settings, then return here and retry.',
        );
      }
      throw const CameraCaptureException(
        'CAMERA_UNAVAILABLE',
        'The camera is unavailable. Return to the app and try again on a device with a camera.',
      );
    }
  }

  Future<CapturedMedia> _persist(
    XFile source,
    MediaKind kind,
    String profileId,
    DocumentType? documentType,
    String captureId,
  ) async {
    final bytes = await source.readAsBytes();
    if (bytes.length > 10 * 1024 * 1024) {
      await _deleteSource(source.path);
      throw const CameraCaptureException(
        'FILE_TOO_LARGE',
        'Photo must be smaller than 10 MB. Please retake it.',
      );
    }
    // Persist before upload: process interruption never requires recapturing an unfinished upload.
    final directory = await _profileDirectory(profileId);
    for (final file in directory.listSync().whereType<File>()) {
      if (file.uri.pathSegments.last.startsWith('${kind.name}_')) {
        await file.delete();
      }
    }
    final extension =
        source.path.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    final file = File(
      '${directory.path}/${kind.name}_${documentType?.apiValue ?? 'photo'}_$captureId.$extension',
    );
    await file.writeAsBytes(bytes, flush: true);
    await _deleteSource(source.path);
    final intent = File('${directory.path}/capture_intent.json');
    if (await intent.exists()) await intent.delete();
    return CapturedMedia(
      kind: kind,
      filePath: file.path,
      bytes: bytes,
      documentType: documentType,
      captureId: captureId,
    );
  }

  Future<void> _deleteSource(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<CapturedMedia?> recover(MediaKind kind, String profileId) async {
    final directory = await _profileDirectory(profileId);
    // Persisted capture intent prevents recovering a selfie as a document after Android activity reclamation.
    final intent = File('${directory.path}/capture_intent.json');
    if (_isAndroid && await intent.exists()) {
      final metadata =
          jsonDecode(await intent.readAsString()) as Map<String, dynamic>;
      if (metadata['kind'] == kind.name) {
        final lost = await _picker.retrieveLostData();
        if (lost.exception != null) {
          await intent.delete();
          throw const CameraCaptureException(
            'CAMERA_INTERRUPTED',
            'Camera capture was interrupted. Please take the photo again.',
          );
        }
        if (lost.files?.isNotEmpty ?? false) {
          final type = metadata['documentType'] == null
              ? null
              : DocumentType.values.firstWhere(
                  (type) => type.apiValue == metadata['documentType'],
                );
          return _persist(
            lost.files!.first,
            kind,
            profileId,
            type,
            metadata['captureId'] as String? ?? _newCaptureId(),
          );
        }
        await intent.delete();
      }
    }
    for (final file in directory.listSync().whereType<File>()) {
      final name = file.uri.pathSegments.last;
      if (!name.startsWith('${kind.name}_')) continue;
      final documentType = kind == MediaKind.document
          ? DocumentType.values.firstWhere(
              (type) => name.contains(type.apiValue),
              orElse: () => DocumentType.passport,
            )
          : null;
      return CapturedMedia(
        kind: kind,
        filePath: file.path,
        bytes: await file.readAsBytes(),
        documentType: documentType,
        captureId: RegExp(
          r'_([a-f0-9]{32})\.(jpg|png)$',
        ).firstMatch(name)?.group(1),
      );
    }
    return null;
  }

  @override
  Future<void> remove(CapturedMedia media) async {
    final file = File(media.filePath);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> discard(String profileId) async {
    final directory = await _profileDirectory(profileId);
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
