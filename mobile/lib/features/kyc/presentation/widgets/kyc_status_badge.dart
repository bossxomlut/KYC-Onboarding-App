import 'package:flutter/material.dart';

import '../../domain/entities/kyc_profile.dart';

class KycStatusAppearance {
  const KycStatusAppearance._({
    required this.foreground,
    required this.background,
    required this.border,
    required this.icon,
  });

  final Color foreground;
  final Color background;
  final Color border;
  final IconData icon;

  static KycStatusAppearance forStatus(KycStatus status) => switch (status) {
    KycStatus.notStarted => const KycStatusAppearance._(
      foreground: Color(0xFF475569),
      background: Color(0xFFF1F5F9),
      border: Color(0xFFCBD5E1),
      icon: Icons.radio_button_unchecked,
    ),
    KycStatus.inProgress => const KycStatusAppearance._(
      foreground: Color(0xFF1D4ED8),
      background: Color(0xFFEFF6FF),
      border: Color(0xFFBFDBFE),
      icon: Icons.edit_note_outlined,
    ),
    KycStatus.pendingReview => const KycStatusAppearance._(
      foreground: Color(0xFF92400E),
      background: Color(0xFFFFFBEB),
      border: Color(0xFFFDE68A),
      icon: Icons.hourglass_top_outlined,
    ),
    KycStatus.verified => const KycStatusAppearance._(
      foreground: Color(0xFF166534),
      background: Color(0xFFF0FDF4),
      border: Color(0xFFBBF7D0),
      icon: Icons.verified_outlined,
    ),
    KycStatus.rejected => const KycStatusAppearance._(
      foreground: Color(0xFF991B1B),
      background: Color(0xFFFEF2F2),
      border: Color(0xFFFECACA),
      icon: Icons.error_outline,
    ),
  };
}

class KycStatusBadge extends StatelessWidget {
  const KycStatusBadge({
    super.key,
    required this.status,
    this.labelKey,
    this.prominent = false,
  });

  final KycStatus status;
  final Key? labelKey;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final appearance = KycStatusAppearance.forStatus(status);
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      label: 'Verification status: ${status.label}',
      liveRegion: true,
      child: ExcludeSemantics(
        child: Container(
          padding: EdgeInsets.all(prominent ? 20 : 12),
          decoration: BoxDecoration(
            color: appearance.background,
            border: Border.all(color: appearance.border),
            borderRadius: BorderRadius.circular(prominent ? 20 : 12),
          ),
          child: Row(
            children: [
              Icon(
                appearance.icon,
                color: appearance.foreground,
                size: prominent ? 32 : 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  status.label,
                  key: labelKey,
                  style:
                      (prominent
                              ? textTheme.headlineSmall
                              : textTheme.titleMedium)
                          ?.copyWith(
                            color: appearance.foreground,
                            fontWeight: FontWeight.w700,
                          ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
