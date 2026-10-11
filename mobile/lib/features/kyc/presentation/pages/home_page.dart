import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/navigation/current_route.dart';
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
      final VoidCallback? onNext = state.busy || profile == null
          ? null
          : () async {
              final cubit = context.read<KycCubit>();
              if (profile.status == KycStatus.rejected &&
                  !await cubit.resubmit()) {
                return;
              }
              if (!context.mounted || !isCurrentRoute(context)) return;
              context.push(cubit.state.profile!.nextStep.routePath);
            };
      return KycScaffold(
        title: 'Identity',
        brandHeader: true,
        signatureHeader: const KycSignatureIntro(
          title: 'A secure start.',
          description: 'Your saved progress is ready.',
        ),
        overlapHeader: true,
        actions: [
          IconButton(
            key: const Key('account-access'),
            tooltip: 'Account access\n$email',
            onPressed: () => context.push('/access'),
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
            if (canReview) ...[
              OutlinedButton.icon(
                key: const Key('review-profiles'),
                onPressed: () => context.push('/reviews'),
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
              _VerificationProgress(profile: profile, onNext: onNext),
              const SizedBox(height: 12),
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
                  first: step == KycStep.personalDetails,
                  last: step == KycStep.review,
                ),
              const SizedBox(height: 16),
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
                onPressed: onNext,
                child: Text(switch (profile.status) {
                  KycStatus.notStarted => 'Start verification',
                  KycStatus.inProgress => 'Continue verification',
                  KycStatus.rejected => 'Resubmit',
                  _ => 'View verification status',
                }),
              ),
            ],
            const SizedBox(height: 4),
            TextButton(
              key: const Key('view-kyc-history'),
              onPressed: () => context.push('/kyc/history'),
              child: const Text(
                'Submission history',
                style: TextStyle(decoration: TextDecoration.underline),
              ),
            ),
            const SizedBox(height: 4),
            const PrivacyNote(text: 'Photos are stored privately.'),
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
  const _VerificationProgress({required this.profile, required this.onNext});

  final KycProfile profile;
  final VoidCallback? onNext;

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
    return Material(
      color: Colors.white,
      elevation: 3,
      shadowColor: AppTheme.ink.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(AppTheme.panelRadius),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 24, 18, 20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'VERIFICATION STATUS',
                        style: textTheme.labelMedium?.copyWith(
                          color: AppTheme.muted,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Semantics(
                        label: 'Verification status: ${profile.status.label}',
                        liveRegion: true,
                        excludeSemantics: true,
                        child: Text(
                          profile.status.label,
                          key: const Key('kyc-status'),
                          style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$completed of ${_verificationTasks.length} completed',
                        style: textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox.square(
                  dimension: 80,
                  child: Stack(
                    fit: StackFit.expand,
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        color: AppTheme.primary,
                        backgroundColor: AppTheme.mint,
                        strokeWidth: 7,
                        strokeCap: StrokeCap.round,
                        value: completed / _verificationTasks.length,
                        semanticsLabel: 'Verification tasks completed',
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Center(
                          child: ExcludeSemantics(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '$completed/${_verificationTasks.length}',
                                style: textTheme.titleMedium?.copyWith(
                                  color: AppTheme.primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: Divider(),
          ),
          InkWell(
            key: const Key('kyc-next-step'),
            onTap: onNext,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
              child: Row(
                children: [
                  Icon(
                    showResult ? appearance.icon : _stepIcon(activeStep),
                    size: 27,
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
                          style: textTheme.bodySmall,
                        ),
                        Text(
                          showResult ? KycStep.result.label : activeStep.label,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 24,
                    color: AppTheme.primary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

IconData _stepIcon(KycStep step) => switch (step) {
  KycStep.personalDetails => Icons.person_rounded,
  KycStep.document => Icons.description_rounded,
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
    required this.first,
    required this.last,
  });

  final KycStep step;
  final _TaskState state;
  final bool correctionRequired;
  final bool awaitingResubmission;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final completed = state == _TaskState.completed;
    final active = state == _TaskState.active;
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
          constraints: const BoxConstraints(minHeight: 64),
          decoration: BoxDecoration(
            color: active ? AppTheme.mint : null,
            borderRadius: BorderRadius.circular(AppTheme.controlRadius),
          ),
          child: CustomPaint(
            painter: _TimelineConnector(first: first, last: last),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: completed || active
                          ? AppTheme.primary
                          : AppTheme.disabledSurface,
                      shape: BoxShape.circle,
                    ),
                    child: completed
                        ? const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 18,
                          )
                        : Text(
                            '${step.index + 1}',
                            textScaler: TextScaler.noScaling,
                            style: textTheme.labelLarge?.copyWith(
                              color: active ? Colors.white : AppTheme.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.label,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(subtitle, style: textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TimelineConnector extends CustomPainter {
  const _TimelineConnector({required this.first, required this.last});

  final bool first;
  final bool last;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(26, first ? size.height / 2 : 0),
      Offset(26, last ? size.height / 2 : size.height),
      Paint()
        ..color = AppTheme.border
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_TimelineConnector oldDelegate) =>
      first != oldDelegate.first || last != oldDelegate.last;
}
