import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kyc_onboarding/features/kyc/data/datasources/camera_datasource.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';

void main() {
  late Directory temporary;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('kyc_media_test_');
  });
  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  test(
    'private interrupted capture stays scoped to profile and is removed after discard',
    () async {
      final folder = await Directory(
        '${temporary.path}/kyc_captures/profile_a',
      ).create(recursive: true);
      await File(
        '${folder.path}/document_national_id.jpg',
      ).writeAsBytes([1, 2, 3]);
      final camera = ImagePickerCameraDataSource(
        directory: () async => temporary,
      );
      expect(await camera.recover(MediaKind.document, 'profile_b'), isNull);
      final media = await camera.recover(MediaKind.document, 'profile_a');
      expect(media!.documentType, DocumentType.nationalId);
      await camera.discard('profile_a');
      expect(await folder.exists(), isFalse);
    },
  );

  test(
    'Android camera restart recovers selfie intent without misclassifying it as document',
    () async {
      final source = File('${temporary.path}/camera_selfie.jpg');
      await source.writeAsBytes([1, 2, 3]);
      final folder = await Directory(
        '${temporary.path}/kyc_captures/profile_a',
      ).create(recursive: true);
      await File(
        '${folder.path}/capture_intent.json',
      ).writeAsString(jsonEncode({'kind': 'selfie', 'documentType': null}));
      final picker = LostPicker(XFile(source.path));
      final camera = ImagePickerCameraDataSource(
        picker: picker,
        directory: () async => temporary,
        isAndroid: true,
      );
      expect(await camera.recover(MediaKind.document, 'profile_a'), isNull);
      expect(picker.calls, 0);
      final media = await camera.recover(MediaKind.selfie, 'profile_a');
      expect(media!.kind, MediaKind.selfie);
      expect(media.documentType, isNull);
      expect(picker.calls, 1);
      expect(await source.exists(), isFalse);
      expect(
        await File('${folder.path}/capture_intent.json').exists(),
        isFalse,
      );
      await camera.remove(media);
      expect(await File(media.filePath).exists(), isFalse);
    },
  );

  test(
    'Android lost document intent preserves chosen driving licence type',
    () async {
      final source = File('${temporary.path}/camera_document.jpg');
      await source.writeAsBytes([1, 2, 3]);
      final folder = await Directory(
        '${temporary.path}/kyc_captures/profile_a',
      ).create(recursive: true);
      await File('${folder.path}/capture_intent.json').writeAsString(
        jsonEncode({'kind': 'document', 'documentType': 'driving_licence'}),
      );
      final camera = ImagePickerCameraDataSource(
        picker: LostPicker(XFile(source.path)),
        directory: () async => temporary,
        isAndroid: true,
      );
      final media = await camera.recover(MediaKind.document, 'profile_a');
      expect(media!.documentType, DocumentType.drivingLicence);
      expect(media.captureId, matches(r'^[a-f0-9]{32}$'));
      final afterRestart = await camera.recover(
        MediaKind.document,
        'profile_a',
      );
      expect(afterRestart!.captureId, media.captureId);
    },
  );
}

class LostPicker extends ImagePicker {
  LostPicker(this.file);
  final XFile file;
  int calls = 0;
  @override
  Future<LostDataResponse> retrieveLostData() async {
    calls++;
    return LostDataResponse(files: [file], type: RetrieveType.image);
  }
}
