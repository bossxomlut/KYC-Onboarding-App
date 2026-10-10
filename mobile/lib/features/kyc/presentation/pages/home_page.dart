import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/identity_brand.dart';
import '../../domain/entities/kyc_profile.dart';
import '../bloc/kyc_cubit.dart';
import '../widgets/kyc_scaffold.dart';
import '../widgets/kyc_status_badge.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.email,
    required this.onLogout,
    this.canReview = false,
  });

  final String email;
  final Future<void> Function() onLogout;
  final bool canReview;

  @override
  Widget build(BuildContext context) => BlocBuilder<KycCubit, KycState>(
    builder: (context, state) {
      final profile = state.profile;
      final textTheme = Theme.of(context).textTheme;
      return KycScaffold(
        title: 'Identity',
        brandHeader: true,
        actions: [
          IconButton(
            key: const Key('account-access'),
            tooltip: 'Account access',
            onPressed: () => context.go('/access'),
            icon: const Icon(Icons.person_outline_rounded),
          ),
          IconButton(
            key: const Key('logout'),
            tooltip: 'Sign out',
            onPressed: state.busy ? null : onLogout,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('A secure start.', style: textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text(
              'Your saved progress is ready.',
              style: textTheme.bodyLarge?.copyWith(color: AppTheme.muted),
            ),
            const SizedBox(height: 8),
            Text(
              email,
              style: textTheme.bodySmall?.copyWith(color: AppTheme.muted),
            ),
            const SizedBox(height: 24),
            if (canReview) ...[
              OutlinedButton.icon(
                key: const Key('review-profiles'),
                onPressed: () => context.go('/reviews'),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Review profiles'),
              ),
              const SizedBox(height: 16),
            ],
            KycError(onRetry: () => context.read<KycCubit>().load()),
            if (state.busy && profile == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (profile != null) ...[
              _VerificationProgress(profile: profile),
              const SizedBox(height: 16),
              for (final step in _verificationTasks)
                _VerificationTask(
                  step: step,
                  state: _taskState(profile, step),
                  correctionRequired:
                      profile.status == KycStatus.rejected &&
                      profile.requiredSteps.contains(step),
                  awaitingResubmission:
                      profile.status == KycStatus.rejected &&
                      step == KycStep.review,
                  last: step == KycStep.review,
                ),
              const SizedBox(height: 20),
              if (profile.status == KycStatus.rejected) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: KycStatusAppearance.forStatus(
                      KycStatus.rejected,
                    ).background,
                    borderRadius: BorderRadius.circular(AppTheme.controlRadius),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.rejectionReason ??
                            'Please update the requested information.',
                        style: textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Required: ${profile.requiredSteps.map((step) => step.label).join(', ')}',
                        style: textTheme.bodySmall?.copyWith(
                          color: AppTheme.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              FilledButton(
                key: const Key('kyc-next'),
                onPressed: state.busy
                    ? null
                    : () async {
                        final cubit = context.read<KycCubit>();
                        if (profile.status == KycStatus.rejected &&
                            !await cubit.resubmit()) {
                          return;
                        }
                        if (!context.mounted) return;
                        context.go(cubit.state.profile!.nextStep.routePath);
                      },
                child: Text(switch (profile.status) {
                  KycStatus.notStarted => 'Start verification',
                  KycStatus.inProgress => 'Continue verification',
                  KycStatus.rejected => 'Resubmit',
                  _ => 'View verification status',
                }),
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              key: const Key('view-kyc-history'),
              onPressed: () => context.go('/kyc/history'),
              child: const Text(
                'Submission history',
                style: TextStyle(decoration: TextDecoration.underline),
              ),
            ),
            const SizedBox(height: 12),
            const PrivacyNote(
              text:
                  'Photos are stored privately. Only you and authorized reviewers can view them after signing in.',
            ),
          ],
        ),
      );
    },
  );
}

const _verificationTasks = [
  KycStep.personalDetails,
  KycStep.document,
  KycStep.selfie,
  KycStep.review,
];

enum _TaskState { completed, active, upcoming }

KycStep _activeStep(KycProfile profile) {
  if (profile.status == KycStatus.rejected) {
    for (final step in _verificationTasks) {
      if (profile.requiredSteps.contains(step)) return step;
    }
    return KycStep.review;
  }
  return profile.nextStep;
}

_TaskState _taskState(KycProfile profile, KycStep step) {
  if (profile.status == KycStatus.verified ||
      profile.status == KycStatus.pendingReview) {
    return _TaskState.completed;
  }
  if (profile.status == KycStatus.rejected) {
    if (step == _activeStep(profile)) return _TaskState.active;
    if (step == KycStep.review || profile.requiredSteps.contains(step)) {
      return _TaskState.upcoming;
    }
    return _TaskState.completed;
  }
  if (step == profile.nextStep) return _TaskState.active;
  return step.index < profile.nextStep.index
      ? _TaskState.completed
      : _TaskState.upcoming;
}

class _VerificationProgress extends StatelessWidget {
  const _VerificationProgress({required this.profile});

  final KycProfile profile;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final appearance = KycStatusAppearance.forStatus(profile.status);
    final completed = _verificationTasks
        .where((step) => _taskState(profile, step) == _TaskState.completed)
        .length;
    final activeStep = _activeStep(profile);
    final showResult =
        profile.status == KycStatus.pendingReview ||
        profile.status == KycStatus.verified;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(AppTheme.panelRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: KycStatusBadge(
                  status: profile.status,
                  labelKey: const Key('kyc-status'),
                  compact: true,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$completed / ${_verificationTasks.length}',
                style: textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            color: appearance.foreground,
            backgroundColor: AppTheme.border,
            borderRadius: BorderRadius.circular(8),
            minHeight: 7,
            value: completed / _verificationTasks.length,
            semanticsLabel: 'Verification tasks completed',
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Icon(
                showResult ? appearance.icon : _stepIcon(activeStep),
                size: 26,
                color: appearance.foreground,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      showResult
                          ? 'Verification status'
                          : profile.status == KycStatus.rejected
                          ? 'Update needed'
                          : 'Next step',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppTheme.muted,
                      ),
                    ),
                    Text(
                      showResult ? KycStep.result.label : activeStep.label,
                      style: textTheme.titleSmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

IconData _stepIcon(KycStep step) => switch (step) {
  KycStep.personalDetails => Icons.person_outline_rounded,
  KycStep.document => Icons.description_outlined,
  KycStep.selfie => Icons.face_outlined,
  KycStep.review => Icons.fact_check_outlined,
  KycStep.result => Icons.verified_user_outlined,
};

class _VerificationTask extends StatelessWidget {
  const _VerificationTask({
    required this.step,
    required this.state,
    required this.correctionRequired,
    required this.awaitingResubmission,
    required this.last,
  });

  final KycStep step;
  final _TaskState state;
  final bool correctionRequired;
  final bool awaitingResubmission;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final completed = state == _TaskState.completed;
    final active = state == _TaskState.active;
    final markerSize = MediaQuery.textScalerOf(context).scale(18) + 18;
    final subtitle = correctionRequired
        ? 'Update required'
        : awaitingResubmission
        ? 'Submit after updates'
        : switch (state) {
            _TaskState.completed => 'Completed',
            _TaskState.active => 'Your next step',
            _TaskState.upcoming => 'Not started',
          };
    return Semantics(
      label: '${step.label}: $subtitle',
      child: ExcludeSemantics(
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: active ? AppTheme.mint : null,
            borderRadius: BorderRadius.circular(AppTheme.controlRadius),
          ),
          child: Row(
            children: [
              Container(
                width: markerSize,
                height: markerSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: completed || active
                      ? AppTheme.primary
                      : AppTheme.border,
                  shape: BoxShape.circle,
                ),
                child: completed
                    ? const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 22,
                      )
                    : Text(
                        '${step.index + 1}',
                        style: textTheme.titleMedium?.copyWith(
                          color: active ? Colors.white : AppTheme.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    border: !active && !last
                        ? const Border(
                            bottom: BorderSide(color: AppTheme.border),
                          )
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(step.label, style: textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: textTheme.bodySmall?.copyWith(
                          color: AppTheme.muted,
                        ),
                      ),
                    ],
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
