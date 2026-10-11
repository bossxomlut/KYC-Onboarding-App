import 'kyc_profile.dart';

/// Renderable camera metadata without exposing a platform controller.
class CaptureCameraSession {
  const CaptureCameraSession({
    required this.kind,
    required this.aspectRatio,
    this.flashEnabled = false,
    this.canToggleFlash = false,
    this.isPreviewMirrored = false,
  });

  final MediaKind kind;

  /// Width / height of the upright preview, including capture orientation.
  final double aspectRatio;
  final bool flashEnabled;
  final bool canToggleFlash;
  final bool isPreviewMirrored;

  @override
  bool operator ==(Object other) =>
      other is CaptureCameraSession &&
      kind == other.kind &&
      aspectRatio == other.aspectRatio &&
      flashEnabled == other.flashEnabled &&
      canToggleFlash == other.canToggleFlash &&
      isPreviewMirrored == other.isPreviewMirrored;

  @override
  int get hashCode => Object.hash(
    kind,
    aspectRatio,
    flashEnabled,
    canToggleFlash,
    isPreviewMirrored,
  );
}
