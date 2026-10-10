import 'dart:typed_data';

import 'package:dio/dio.dart';

class ApiClient {
  ApiClient(this.dio);
  final Dio dio;

  Future<Map<String, dynamic>> get(String path) async =>
      _map((await dio.get<Object?>(path)).data);

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
  }) async => _map((await dio.post<Object?>(path, data: data)).data);

  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? data,
  }) async => _map((await dio.put<Object?>(path, data: data)).data);

  Future<Map<String, dynamic>> upload(
    String path,
    String filePath, {
    Map<String, dynamic>? fields,
    void Function(int sent, int total)? onProgress,
  }) async {
    final extension = filePath.toLowerCase().split('.').last;
    final mimeType = extension == 'png'
        ? 'image/png'
        : (extension == 'jpg' || extension == 'jpeg'
              ? 'image/jpeg'
              : 'application/octet-stream');
    final form = FormData.fromMap({
      ...?fields,
      'file': await MultipartFile.fromFile(
        filePath,
        contentType: DioMediaType.parse(mimeType),
      ),
    });
    return _map(
      (await dio.post<Object?>(
        path,
        data: form,
        onSendProgress: onProgress,
      )).data,
    );
  }

  Future<Uint8List> bytes(String path) async {
    final response = await dio.get<List<int>>(
      path,
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data!);
  }

  Map<String, dynamic> _map(Object? data) {
    if (data is Map<String, dynamic>) return data;
    throw const FormatException('Unexpected server response.');
  }
}
