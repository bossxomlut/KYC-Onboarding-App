import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

/// A preparation or uploaded state when a private preview is unavailable.
class CapturePreparation extends StatelessWidget {
  const CapturePreparation({
    super.key,
    required this.isDocument,
    this.hasUploadedPhoto = false,
  });

  final bool isDocument;
  final bool hasUploadedPhoto;

  @override
  Widget build(BuildContext context) => Semantics(
    label: hasUploadedPhoto
        ? (isDocument
              ? 'Document photo uploaded; preview unavailable'
              : 'Selfie photo uploaded; preview unavailable')
        : (isDocument ? 'No document photo yet' : 'No selfie photo yet'),
    child: ExcludeSemantics(
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.mint,
          border: Border.all(color: AppTheme.primary.withValues(alpha: .14)),
          borderRadius: BorderRadius.circular(AppTheme.panelRadius),
        ),
        child: CustomPaint(
          painter: const _CaptureFramePainter(),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  hasUploadedPhoto
                      ? const Icon(
                          Icons.cloud_done_outlined,
                          color: AppTheme.primary,
                          size: 54,
                        )
                      : isDocument
                      ? const _DocumentIllustration()
                      : Container(
                          width: 116,
                          height: 136,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .68),
                            border: Border.all(
                              color: AppTheme.primary.withValues(alpha: .4),
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(58),
                          ),
                          child: const Icon(
                            Icons.person_outline_rounded,
                            color: AppTheme.primary,
                            size: 76,
                          ),
                        ),
                  const SizedBox(height: 16),
                  Text(
                    hasUploadedPhoto ? 'Photo uploaded' : 'No photo yet',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: AppTheme.primary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _DocumentIllustration extends StatelessWidget {
  const _DocumentIllustration();

  @override
  Widget build(BuildContext context) => Container(
    width: 188,
    height: 110,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .68),
      border: Border.all(
        color: AppTheme.primary.withValues(alpha: .6),
        width: 1.5,
      ),
      borderRadius: BorderRadius.circular(AppTheme.controlRadius),
    ),
    child: Row(
      children: [
        Container(
          width: 60,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.person_rounded,
            color: AppTheme.primary,
            size: 52,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _line(1),
              const SizedBox(height: 10),
              _line(.8),
              const SizedBox(height: 10),
              _line(.58),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _line(double width) => FractionallySizedBox(
    widthFactor: width,
    child: Container(
      height: 7,
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(4),
      ),
    ),
  );
}

class _CaptureFramePainter extends CustomPainter {
  const _CaptureFramePainter();

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 15.0;
    const length = 16.0;
    final paint = Paint()
      ..color = AppTheme.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(inset, inset + length)
      ..lineTo(inset, inset + 4)
      ..quadraticBezierTo(inset, inset, inset + 4, inset)
      ..lineTo(inset + length, inset)
      ..moveTo(size.width - inset - length, inset)
      ..lineTo(size.width - inset - 4, inset)
      ..quadraticBezierTo(
        size.width - inset,
        inset,
        size.width - inset,
        inset + 4,
      )
      ..lineTo(size.width - inset, inset + length)
      ..moveTo(size.width - inset, size.height - inset - length)
      ..lineTo(size.width - inset, size.height - inset - 4)
      ..quadraticBezierTo(
        size.width - inset,
        size.height - inset,
        size.width - inset - 4,
        size.height - inset,
      )
      ..lineTo(size.width - inset - length, size.height - inset)
      ..moveTo(inset + length, size.height - inset)
      ..lineTo(inset + 4, size.height - inset)
      ..quadraticBezierTo(
        inset,
        size.height - inset,
        inset,
        size.height - inset - 4,
      )
      ..lineTo(inset, size.height - inset - length);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CaptureFramePainter oldDelegate) => false;
}
