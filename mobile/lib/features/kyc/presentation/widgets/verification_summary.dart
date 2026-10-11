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

    final disabled = result.status == VerificationStatus.disabled;
    final hasResults =
        result.ocr != null ||
        result.faceMatch != null ||
        result.status == VerificationStatus.completed ||
        result.status == VerificationStatus.failed;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
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
                  'Automated checks',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (disabled)
            const Text(
              'Automated checks are unavailable. A reviewer will check your documents manually.',
            )
          else ...[
            if (result.status == VerificationStatus.notStarted)
              const Text('Automated checks have not run for these photos yet.'),
            if (result.status == VerificationStatus.failed)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Automated checks could not complete. A reviewer will check your documents manually.',
                ),
              ),
            if (result.checkedAt != null) ...[
              Text(
                'Checked ${DateFormat('d MMM yyyy, HH:mm', 'en_US').format(result.checkedAt!.toLocal())}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
            ],
            if (hasResults) ...[
              _ocr(context, result.ocr),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              _face(context, result.faceMatch),
              const SizedBox(height: 12),
              Text(
                'This compares the selfie with the document photo. It does not check liveness or prove identity. A reviewer makes the final decision.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _ocr(BuildContext context, OcrVerification? ocr) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Document text (OCR)',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      if (ocr == null)
        const Text('OCR result unavailable.')
      else if (ocr.status == OcrStatus.noText)
        const Text('No document text was recognized.')
      else if (ocr.status == OcrStatus.failed)
        const Text('Document text recognition could not complete.')
      else ...[
        const Text(
          'Compare these details with the document and entered personal details.',
        ),
        const SizedBox(height: 12),
        if (ocr.fields.fullName != null)
          _field(context, 'Extracted full name', ocr.fields.fullName!),
        if (ocr.fields.dateOfBirth != null)
          _field(context, 'Extracted date of birth', ocr.fields.dateOfBirth!),
        if (ocr.fields.documentNumber != null)
          _field(
            context,
            'Extracted document number',
            ocr.fields.documentNumber!,
          ),
        if (ocr.fields.fullName == null &&
            ocr.fields.dateOfBirth == null &&
            ocr.fields.documentNumber == null)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'No structured details were extracted. Review the document text manually.',
            ),
          ),
        if (ocr.confidence != null && ocr.confidence!.isFinite)
          Text('OCR confidence: ${_score(ocr.confidence!)}%'),
        if (ocr.text.trim().isNotEmpty)
          Material(
            type: MaterialType.transparency,
            child: ExpansionTile(
              key: const Key('recognized-document-text'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              title: const Text('Recognized document text'),
              children: [SelectableText(ocr.text)],
            ),
          ),
      ],
    ],
  );

  Widget _face(BuildContext context, FaceMatchVerification? face) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Face comparison', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text(switch (face?.status) {
        null => 'Face comparison unavailable.',
        FaceMatchStatus.matched => 'Faces are similar',
        FaceMatchStatus.notMatched => 'Faces are below the match threshold',
        FaceMatchStatus.noFace =>
          'A face could not be detected in one or both photos.',
        FaceMatchStatus.multipleFaces =>
          'Multiple faces were detected. Review the photos manually.',
        FaceMatchStatus.failed => 'Face comparison could not complete.',
      }),
      if (face?.status == FaceMatchStatus.matched ||
          face?.status == FaceMatchStatus.notMatched) ...[
        const SizedBox(height: 8),
        if (face!.similarity != null && face.similarity!.isFinite)
          Text('Similarity score: ${_score(face.similarity!)} / 100'),
        Text('Match threshold: ${_score(face.threshold)} / 100'),
      ],
    ],
  );

  Widget _field(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 3),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
        ),
      ],
    ),
  );

  String _score(double value) =>
      value.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
}
