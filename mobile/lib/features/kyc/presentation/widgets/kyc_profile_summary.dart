import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/kyc_profile.dart';
import 'kyc_scaffold.dart';
import 'kyc_status_badge.dart';

class KycProfileSummary extends StatelessWidget {
  const KycProfileSummary({
    super.key,
    required this.profile,
    required this.media,
    this.onEdit,
  });

  final KycProfile? profile;
  final Map<MediaKind, Uint8List> media;
  final ValueChanged<KycStep>? onEdit;

  @override
  Widget build(BuildContext context) {
    final details = profile?.personalDetails;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (profile != null) ...[
          Text(
            'Verification status',
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: AppTheme.muted),
          ),
          const SizedBox(height: 8),
          KycStatusBadge(status: profile!.status),
          const SizedBox(height: 20),
        ],
        _section(
          context,
          title: 'Personal details',
          step: KycStep.personalDetails,
          icon: Icons.person_outline,
          children: [
            if (details == null)
              const Text('Personal details are incomplete.')
            else ...[
              _detail(context, 'Full name', details.fullName),
              _detail(
                context,
                'Date of birth',
                _birthDate(details.dateOfBirth),
              ),
              _detail(context, 'Nationality', details.nationality),
              _detail(context, 'Residential address', details.address),
              _detail(
                context,
                'Document number',
                details.documentNumber,
                last: true,
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        _section(
          context,
          title: 'ID document',
          step: KycStep.document,
          icon: Icons.badge_outlined,
          children: [
            if (profile?.document?.documentType != null) ...[
              Text(
                profile!.document!.documentType!.label,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
              ),
              const SizedBox(height: 12),
            ],
            PrivatePhoto(
              bytes: media[MediaKind.document],
              label: 'Your private document photo',
            ),
          ],
        ),
        const SizedBox(height: 16),
        _section(
          context,
          title: 'Selfie',
          step: KycStep.selfie,
          icon: Icons.face_outlined,
          children: [
            PrivatePhoto(
              bytes: media[MediaKind.selfie],
              label: 'Your private selfie photo',
            ),
          ],
        ),
      ],
    );
  }

  String _birthDate(String value) {
    final date = DateTime.tryParse(value);
    return date == null
        ? value
        : DateFormat('d MMMM yyyy', 'en_US').format(date);
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required KycStep step,
    required IconData icon,
    required List<Widget> children,
  }) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: AppTheme.border),
      borderRadius: BorderRadius.circular(AppTheme.panelRadius),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(context, title, step, icon),
        const SizedBox(height: 14),
        ...children,
      ],
    ),
  );

  Widget _heading(
    BuildContext context,
    String title,
    KycStep step,
    IconData icon,
  ) => Row(
    children: [
      Icon(icon, size: 20, color: AppTheme.primary),
      const SizedBox(width: 8),
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      if ((profile?.canEdit ?? false) && onEdit != null)
        TextButton(onPressed: () => onEdit!(step), child: const Text('Edit')),
    ],
  );

  Widget _detail(
    BuildContext context,
    String label,
    String value, {
    bool last = false,
  }) => Padding(
    padding: EdgeInsets.only(bottom: last ? 0 : 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppTheme.muted),
        ),
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
}
