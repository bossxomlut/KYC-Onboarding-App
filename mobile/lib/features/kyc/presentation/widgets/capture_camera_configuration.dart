import 'package:flutter/widgets.dart';

import '../bloc/capture_camera_cubit.dart';

/// The composition root supplies the camera session and its platform preview.
class CaptureCameraConfiguration {
  const CaptureCameraConfiguration({
    required this.createCubit,
    required this.previewBuilder,
  });

  final CaptureCameraCubit Function() createCubit;
  final WidgetBuilder previewBuilder;
}
