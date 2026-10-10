import 'dart:typed_data';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/kyc_profile.dart';
import '../models/kyc_profile_model.dart';

class KycRemoteDataSource {
  const KycRemoteDataSource(this.api);
  final ApiClient api;
  Future<KycProfile> load() async => _profile(await api.get('/kyc'));
  Future<KycProfile> saveDetails(PersonalDetails details) async => _profile(
    await api.put(
      '/kyc/personal-details',
      data: KycProfileModel.detailsJson(details),
    ),
  );
  Future<KycProfile> upload(
    CapturedMedia media, {
    void Function(int, int)? onProgress,
  }) async => _profile(
    await api.upload(
      '/kyc/media/${media.kind.name}',
      media.filePath,
      fields: {
        if (media.documentType != null)
          'documentType': media.documentType!.apiValue,
        if (media.captureId != null) 'captureId': media.captureId!,
      },
      onProgress: onProgress,
    ),
  );
  Future<Uint8List> privateMedia(MediaKind kind) =>
      api.bytes('/kyc/media/${kind.name}');
  Future<KycProfile> submit() async => _profile(await api.post('/kyc/submit'));
  Future<KycProfile> resubmit() async =>
      _profile(await api.post('/kyc/resubmit'));
  KycProfile _profile(Map<String, dynamic> json) =>
      KycProfileModel.fromJson(json['profile'] as Map<String, dynamic>);
}
