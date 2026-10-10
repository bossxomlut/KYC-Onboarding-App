import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          KycStatusBadge(status: profile!.status),
          const SizedBox(height: 24),
        ],
        _heading(context, 'Personal details', KycStep.personalDetails),
        const SizedBox(height: 8),
        if (details == null)
          const Text('Personal details are incomplete.')
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detail(context, 'Full name', details.fullName),
                  _detail(
                    context,
                    'Date of birth',
                    _birthDate(details.dateOfBirth),
                  ),
                  _detail(context, 'Nationality', details.nationality),
                  _detail(context, 'Residential address', details.address),
                  _detail(context, 'Document number', details.documentNumber),
                ],
              ),
            ),
          ),
        const SizedBox(height: 20),
        _heading(context, 'ID document', KycStep.document),
        if (profile?.document?.documentType != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(profile!.document!.documentType!.label),
          ),
        PrivatePhoto(
          bytes: media[MediaKind.document],
          label: 'Your private document photo',
        ),
        const SizedBox(height: 20),
        _heading(context, 'Selfie', KycStep.selfie),
        const SizedBox(height: 8),
        PrivatePhoto(
          bytes: media[MediaKind.selfie],
          label: 'Your private selfie photo',
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

  Widget _heading(BuildContext context, String title, KycStep step) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      if ((profile?.canEdit ?? false) && onEdit != null)
        TextButton(onPressed: () => onEdit!(step), child: const Text('Edit')),
    ],
  );

  Widget _detail(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 3),
        Text(value),
      ],
    ),
  );
}
