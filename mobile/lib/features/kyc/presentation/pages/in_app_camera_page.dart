import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/kyc_profile.dart';
import '../bloc/capture_camera_cubit.dart';
import '../widgets/capture_camera_overlay.dart';

class InAppCameraPage extends StatefulWidget {
  const InAppCameraPage({
    super.key,
    required this.kind,
    this.documentType,
    required this.previewBuilder,
    required this.onCapture,
  });

  final MediaKind kind;
  final DocumentType? documentType;
  final WidgetBuilder previewBuilder;
  final Future<bool> Function() onCapture;

  @override
  State<InAppCameraPage> createState() => _InAppCameraPageState();
}

class _InAppCameraPageState extends State<InAppCameraPage>
    with WidgetsBindingObserver {
  late final CaptureCameraCubit _camera;
  bool _capturing = false;
  bool _closing = false;
  bool _captureFailed = false;

  bool get _isDocument => widget.kind == MediaKind.document;

  @override
  void initState() {
    super.initState();
    _camera = context.read<CaptureCameraCubit>();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_camera.initialize(widget.kind));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_camera.resume());
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      unawaited(_camera.pause());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _capture() async {
    if (_capturing || _closing || !_camera.state.isReady) return;
    setState(() {
      _capturing = true;
      _captureFailed = false;
    });
    var success = false;
    try {
      success = await widget.onCapture();
      if (success) await _camera.pause();
    } catch (_) {
      success = false;
    } finally {
      if (mounted) {
        setState(() {
          _capturing = false;
          _captureFailed = !success;
        });
        if (success && ModalRoute.of(context)?.isCurrent == true) {
          Navigator.of(context).pop(true);
        }
      }
    }
  }

  Future<void> _cancel() async {
    if (_capturing || _closing) return;
    setState(() => _closing = true);
    await _camera.pause();
    if (!mounted) return;
    setState(() => _closing = false);
    if (ModalRoute.of(context)?.isCurrent == true) {
      Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: AppTheme.cameraBackdrop,
    ),
    child: PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_cancel());
      },
      child: Scaffold(
        backgroundColor: AppTheme.cameraBackdrop,
        body: BlocBuilder<CaptureCameraCubit, CaptureCameraState>(
          builder: (context, state) => LayoutBuilder(
            builder: (context, constraints) {
              final landscape = constraints.maxWidth > constraints.maxHeight;
              final compact = constraints.maxHeight < 640;
              final availableHeight =
                  constraints.maxHeight -
                  MediaQuery.paddingOf(context).vertical;
              final largeControls =
                  compact && MediaQuery.textScalerOf(context).scale(1) > 1.3;
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (state.isReady && state.session != null)
                    _CameraPreview(
                      aspectRatio: state.session!.aspectRatio,
                      builder: widget.previewBuilder,
                    ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppTheme.cameraBackdrop.withValues(alpha: .8),
                          Colors.transparent,
                          Colors.transparent,
                          AppTheme.cameraBackdrop.withValues(alpha: .87),
                        ],
                        stops: [0, .3, .65, 1],
                      ),
                    ),
                  ),
                  SafeArea(
                    child: landscape
                        ? Row(
                            children: [
                              Expanded(
                                child: Column(
                                  children: [
                                    _boundedHeader(
                                      compact: true,
                                      maxHeight: availableHeight * .42,
                                    ),
                                    Expanded(child: _viewfinder(state)),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: constraints.maxWidth * .32,
                                child: Center(
                                  child: SingleChildScrollView(
                                    child: _controls(
                                      state,
                                      landscape: true,
                                      largeControls: largeControls,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              _boundedHeader(
                                compact: compact,
                                maxHeight: availableHeight * .36,
                              ),
                              Expanded(child: _viewfinder(state)),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight: availableHeight * .46,
                                ),
                                child: SingleChildScrollView(
                                  child: _controls(
                                    state,
                                    largeControls: largeControls,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );

  Widget _boundedHeader({required bool compact, required double maxHeight}) =>
      ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(child: _header(compact: compact)),
      );

  Widget _header({required bool compact}) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Close camera',
              onPressed: _capturing || _closing ? null : _cancel,
              style: IconButton.styleFrom(
                backgroundColor: Colors.black.withValues(alpha: .22),
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white38,
                minimumSize: const Size(48, 48),
              ),
              icon: const Icon(Icons.close_rounded),
            ),
            const Spacer(),
            Flexible(
              flex: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .26),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .16),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isDocument
                          ? Icons.camera_rear_outlined
                          : Icons.camera_front_outlined,
                      color: AppTheme.cameraGuide,
                      size: 17,
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        _isDocument ? 'Rear camera' : 'Front camera',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 12 : 22),
        Text(
          _isDocument
              ? 'Frame your ${switch (widget.documentType) {
                  DocumentType.nationalId => 'ID card',
                  DocumentType.drivingLicence => 'driving licence',
                  _ => 'passport',
                }}'
              : 'A clear view of you',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 19 : 25,
            fontWeight: FontWeight.w600,
            height: 1.15,
            letterSpacing: -.5,
          ),
        ),
        if (!compact || MediaQuery.textScalerOf(context).scale(1) <= 1.3) ...[
          const SizedBox(height: 8),
          Text(
            _isDocument
                ? (widget.documentType == DocumentType.passport
                      ? 'Keep the entire photo page inside the frame.'
                      : 'Keep every edge inside the frame.')
                : 'Centre your face in the oval and look straight ahead.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .8),
              fontSize: compact ? 12 : 14,
              height: 1.35,
            ),
          ),
        ],
      ],
    ),
  );

  Widget _viewfinder(CaptureCameraState state) {
    if (state.isReady) {
      return CaptureCameraOverlay(
        kind: widget.kind,
        documentType: widget.documentType,
      );
    }
    if (state.failure != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_outlined,
              color: AppTheme.cameraGuide,
              size: 36,
            ),
            const SizedBox(height: 12),
            const Text(
              'Camera unavailable',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              state.failure!.message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('camera-retry'),
              onPressed: () => _camera.initialize(widget.kind),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              color: AppTheme.cameraGuide,
              strokeWidth: 2.5,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            state.status == CaptureCameraStatus.paused
                ? 'Camera paused'
                : 'Starting camera…',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _controls(
    CaptureCameraState state, {
    bool landscape = false,
    bool largeControls = false,
  }) => Container(
    width: double.infinity,
    margin: EdgeInsets.fromLTRB(16, 12, 16, landscape ? 12 : 16),
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    decoration: BoxDecoration(
      color: AppTheme.cameraBackdrop.withValues(alpha: .86),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white.withValues(alpha: .12)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_captureFailed)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              'Photo could not be saved. Please try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.cameraGuide,
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ),
        if (state.isReady && state.failure != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              state.failure!.message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.cameraGuide,
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ),
        Text(
          largeControls
              ? 'Good light'
              : _isDocument
              ? 'Good light · No glare'
              : 'Good light · No hats or sunglasses',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!landscape) const SizedBox(width: 48),
            if (!landscape) const Spacer(),
            Container(
              width: 78,
              height: 78,
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: state.isReady ? AppTheme.cameraGuide : Colors.white30,
                  width: 2,
                ),
              ),
              child: IconButton(
                key: const Key('camera-shutter'),
                tooltip: _isDocument ? 'Take document photo' : 'Take selfie',
                onPressed: state.isReady && !_capturing && !_closing
                    ? _capture
                    : null,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  disabledBackgroundColor: Colors.white.withValues(alpha: .2),
                  foregroundColor: AppTheme.primary,
                  disabledForegroundColor: Colors.white38,
                  padding: EdgeInsets.zero,
                ),
                icon: _capturing
                    ? const SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                          color: AppTheme.cameraGuide,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Icon(Icons.camera_alt_rounded, size: 30),
              ),
            ),
            if (!landscape) const Spacer(),
            if (!landscape) SizedBox(width: 48, child: _flash(state)),
          ],
        ),
        if (landscape) _flash(state),
        const SizedBox(height: 10),
        Text(
          _capturing
              ? (largeControls ? 'Saving…' : 'Saving photo…')
              : (largeControls ? 'Take photo' : 'Tap to take photo'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );

  Widget _flash(CaptureCameraState state) {
    if (!_isDocument || state.session?.canToggleFlash != true) {
      return const SizedBox.shrink();
    }
    final enabled = state.session!.flashEnabled;
    return IconButton(
      tooltip: enabled ? 'Turn flash off' : 'Turn flash on',
      onPressed: state.isReady && !_capturing && !_closing
          ? _camera.toggleFlash
          : null,
      style: IconButton.styleFrom(
        foregroundColor: enabled ? AppTheme.cameraGuide : Colors.white70,
        minimumSize: const Size(48, 48),
      ),
      icon: Icon(enabled ? Icons.flash_on_rounded : Icons.flash_off_rounded),
    );
  }
}

class _CameraPreview extends StatelessWidget {
  const _CameraPreview({required this.aspectRatio, required this.builder});

  final double aspectRatio;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final ratio = aspectRatio.isFinite && aspectRatio > 0
          ? aspectRatio
          : 3 / 4;
      return ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: constraints.maxHeight * ratio,
            height: constraints.maxHeight,
            child: builder(context),
          ),
        ),
      );
    },
  );
}
