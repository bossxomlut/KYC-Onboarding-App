import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/kyc_profile.dart';

class CaptureCameraOverlay extends StatelessWidget {
  const CaptureCameraOverlay({
    super.key,
    required this.kind,
    this.documentType,
  });

  final MediaKind kind;
  final DocumentType? documentType;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final isDocument = kind == MediaKind.document;
      final aspectRatio = isDocument
          ? (documentType == DocumentType.passport ? 1.42 : 1.586)
          : .74;
      final maxWidth = math.min(
        constraints.maxWidth * (isDocument ? .88 : .72),
        isDocument ? 580.0 : 300.0,
      );
      final maxHeight = constraints.maxHeight * .9;
      final width = math.min(maxWidth, maxHeight * aspectRatio);
      final height = width / aspectRatio;
      final guide = Rect.fromCenter(
        center: Offset(constraints.maxWidth / 2, constraints.maxHeight / 2),
        width: width,
        height: height,
      );
      return Semantics(
        label: isDocument
            ? 'Document frame. Keep every edge inside the frame. Avoid glare.'
            : 'Face guide. Centre your face inside the oval. Look straight ahead without hats or sunglasses.',
        child: IgnorePointer(
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _CaptureGuidePainter(
                    guide: guide,
                    isDocument: isDocument,
                  ),
                ),
              ),
              Positioned.fromRect(
                rect: guide,
                child: SizedBox(
                  key: Key(
                    isDocument
                        ? 'document-camera-guide'
                        : 'selfie-camera-guide',
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _CaptureGuidePainter extends CustomPainter {
  const _CaptureGuidePainter({required this.guide, required this.isDocument});

  final Rect guide;
  final bool isDocument;

  @override
  void paint(Canvas canvas, Size size) {
    final cutout = Path();
    final roundedGuide = RRect.fromRectAndRadius(
      guide,
      const Radius.circular(14),
    );
    if (isDocument) {
      cutout.addRRect(roundedGuide);
    } else {
      cutout.addOval(guide);
    }
    final mask = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addPath(cutout, Offset.zero);
    canvas.drawPath(
      mask,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: .46),
            Colors.black.withValues(alpha: .46),
            Colors.transparent,
          ],
          stops: const [0, .14, .86, 1],
        ).createShader(Offset.zero & size),
    );
    final outline = Paint()
      ..color = Colors.white.withValues(alpha: .58)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawPath(cutout, outline);

    final accent = Paint()
      ..color = AppTheme.cameraGuide
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 3.5;
    if (isDocument) {
      final length = math.min(30.0, guide.shortestSide * .22);
      const radius = 14.0;
      final corners = Path()
        ..moveTo(guide.left, guide.top + length)
        ..lineTo(guide.left, guide.top + radius)
        ..quadraticBezierTo(
          guide.left,
          guide.top,
          guide.left + radius,
          guide.top,
        )
        ..lineTo(guide.left + length, guide.top)
        ..moveTo(guide.right - length, guide.top)
        ..lineTo(guide.right - radius, guide.top)
        ..quadraticBezierTo(
          guide.right,
          guide.top,
          guide.right,
          guide.top + radius,
        )
        ..lineTo(guide.right, guide.top + length)
        ..moveTo(guide.right, guide.bottom - length)
        ..lineTo(guide.right, guide.bottom - radius)
        ..quadraticBezierTo(
          guide.right,
          guide.bottom,
          guide.right - radius,
          guide.bottom,
        )
        ..lineTo(guide.right - length, guide.bottom)
        ..moveTo(guide.left + length, guide.bottom)
        ..lineTo(guide.left + radius, guide.bottom)
        ..quadraticBezierTo(
          guide.left,
          guide.bottom,
          guide.left,
          guide.bottom - radius,
        )
        ..lineTo(guide.left, guide.bottom - length);
      canvas.drawPath(corners, accent);
    } else {
      canvas.drawArc(guide, -math.pi * .72, math.pi * .44, false, accent);
      canvas.drawArc(guide, math.pi * .28, math.pi * .44, false, accent);
    }
  }

  @override
  bool shouldRepaint(_CaptureGuidePainter oldDelegate) =>
      guide != oldDelegate.guide || isDocument != oldDelegate.isDocument;
}
