import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/kyc_profile.dart';

class VerificationSummary extends StatelessWidget {
  const VerificationSummary({super.key, required this.verification});

  final KycVerification? verification;

  @override
  Widget build(BuildContext context) {
    final result = verification;
    if (result == null) return const SizedBox.shrink();

    final hasResults =
        result.ocr != null ||
        result.selfieFace != null ||
        result.faceMatch != null ||
        result.status == VerificationStatus.completed ||
        result.status == VerificationStatus.failed;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(AppTheme.panelRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.fact_check_outlined,
                size: 20,
                color: AppTheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Identity checks',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.cardSpacing),
          if (result.status == VerificationStatus.disabled)
            _row(context, 'Status', 'Unavailable')
          else if (result.status == VerificationStatus.notStarted)
            _row(context, 'Status', 'Not run')
          else if (result.status == VerificationStatus.failed &&
              result.ocr == null &&
              result.selfieFace == null &&
              result.faceMatch == null)
            _row(context, 'Status', 'Check failed')
          else if (hasResults) ...[
            _ocr(context, result.ocr),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(),
            ),
            _row(context, 'Selfie', switch (result.selfieFace?.status) {
              null => 'Not recorded',
              SelfieFaceStatus.detected => 'Face detected',
              SelfieFaceStatus.noFace => 'No face',
              SelfieFaceStatus.multipleFaces => 'Multiple faces',
              SelfieFaceStatus.failed => 'Check failed',
            }),
            _face(context, result.faceMatch),
            const SizedBox(height: 4),
            Text(
              'No liveness check',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (result.checkedAt != null) ...[
            const SizedBox(height: 8),
            Text(
              'Checked ${DateFormat('d MMM yyyy, HH:mm', 'en_US').format(result.checkedAt!.toLocal())}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _ocr(BuildContext context, OcrVerification? ocr) {
    final status = switch (ocr?.status) {
      null => 'Unavailable',
      OcrStatus.succeeded => 'Extracted',
      OcrStatus.noText => 'No text',
      OcrStatus.failed => 'Check failed',
    };
    final confidence = ocr?.confidence;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _row(
          context,
          'OCR',
          ocr?.status == OcrStatus.succeeded &&
                  confidence != null &&
                  confidence.isFinite
              ? '$status · ${_score(confidence)}% confidence'
              : status,
        ),
        if (ocr != null) ...[
          _row(context, 'Name', _value(ocr.fields.fullName)),
          _row(context, 'Date of birth', _value(ocr.fields.dateOfBirth)),
          _row(context, 'Document no.', _value(ocr.fields.documentNumber)),
          if (ocr.text.trim().isNotEmpty)
            Material(
              type: MaterialType.transparency,
              child: ExpansionTile(
                key: const Key('recognized-document-text'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                visualDensity: VisualDensity.compact,
                title: Text(
                  'OCR text',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                children: [SelectableText(ocr.text)],
              ),
            ),
        ],
      ],
    );
  }

  Widget _face(BuildContext context, FaceMatchVerification? face) {
    final status = switch (face?.status) {
      null => 'Unavailable',
      FaceMatchStatus.matched => 'Match',
      FaceMatchStatus.notMatched => 'No match',
      FaceMatchStatus.noFace => 'No face',
      FaceMatchStatus.multipleFaces => 'Multiple faces',
      FaceMatchStatus.failed => 'Check failed',
    };
    final similarity = face?.similarity;
    final hasScore =
        (face?.status == FaceMatchStatus.matched ||
            face?.status == FaceMatchStatus.notMatched) &&
        similarity != null &&
        similarity.isFinite;
    return _row(
      context,
      'Face match',
      status,
      detail: hasScore
          ? 'Score ${_score(similarity)} / 100 · threshold ${_score(face!.threshold)}'
          : null,
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    String value, {
    String? detail,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final labelText = Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        );
        final valueText = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            ),
            if (detail != null)
              Text(detail, style: Theme.of(context).textTheme.bodySmall),
          ],
        );
        if (constraints.maxWidth < 260 ||
            MediaQuery.textScalerOf(context).scale(14) > 21) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [labelText, const SizedBox(height: 2), valueText],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 96, child: labelText),
            const SizedBox(width: 12),
            Expanded(child: valueText),
          ],
        );
      },
    ),
  );

  String _value(String? value) =>
      value == null || value.trim().isEmpty ? '—' : value;

  String _score(double value) =>
      value.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
}
