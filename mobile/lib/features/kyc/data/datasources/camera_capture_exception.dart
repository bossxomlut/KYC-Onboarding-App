class CameraCaptureException implements Exception {
  const CameraCaptureException(this.code, this.message);
  final String code;
  final String message;
}
