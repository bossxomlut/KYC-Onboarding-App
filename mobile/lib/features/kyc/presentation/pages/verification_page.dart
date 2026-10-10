import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/navigation/current_route.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/kyc_profile.dart';
import '../bloc/kyc_cubit.dart';
import '../widgets/kyc_scaffold.dart';
import '../widgets/kyc_status_badge.dart';
import '../widgets/submitted_profile_sheet.dart';

class VerificationPage extends StatefulWidget {
  const VerificationPage({super.key});
  @override
  State<VerificationPage> createState() => _VerificationPageState();
}

class _VerificationPageState extends State<VerificationPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<KycCubit>().load();
    });
  }

  Future<void> _viewSubmittedProfile() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: false,
    useSafeArea: true,
    builder: (_) => BlocProvider.value(
      value: context.read<KycCubit>(),
      child: const SubmittedProfileSheet(),
    ),
  );

  @override
  Widget build(BuildContext context) => BlocBuilder<KycCubit, KycState>(
    builder: (context, state) {
      final profile = state.profile;
      final status = profile?.status;
      final rejected = status == KycStatus.rejected;
      final verified = status == KycStatus.verified;
      final appearance = status == null
          ? null
          : KycStatusAppearance.forStatus(status);
      return KycScaffold(
        title: 'Verification status',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'VERIFICATION RESULT',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppTheme.muted,
                letterSpacing: .8,
              ),
            ),
            const SizedBox(height: 12),
            if (status != null)
              KycStatusBadge(status: status, prominent: true)
            else
              Text(
                'Loading your status…',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            const SizedBox(height: 16),
            Text(
              verified
                  ? 'Your identity has been verified. You’re all set.'
                  : rejected
                  ? 'A few updates are needed before we can verify your identity.'
                  : status == KycStatus.pendingReview
                  ? 'Your profile has been submitted. Refresh here to see the latest review result.'
                  : 'Continue your verification to complete the remaining steps.',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: AppTheme.muted),
            ),
            const SizedBox(height: 24),
            KycError(onRetry: () => context.read<KycCubit>().load()),
            if (state.busy) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 16),
            ],
            if (rejected) ...[
              Card(
                color: appearance!.background,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.panelRadius),
                  side: BorderSide(color: appearance.border),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Why it needs an update',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: appearance.foreground),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        profile!.rejectionReason ??
                            'Please update the requested information.',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Update: ${profile.requiredSteps.map((step) => step.label).join(', ')}',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('resubmit-kyc'),
                onPressed: state.busy
                    ? null
                    : () async {
                        final cubit = context.read<KycCubit>();
                        final success = await cubit.resubmit();
                        if (success &&
                            context.mounted &&
                            isCurrentRoute(context)) {
                          context.go(cubit.state.profile!.nextStep.routePath);
                        }
                      },
                child: const Text('Update and resubmit'),
              ),
            ],
            if (rejected) const SizedBox(height: 20),
            if (status == KycStatus.pendingReview || rejected || verified) ...[
              OutlinedButton.icon(
                key: const Key('view-submitted-profile'),
                onPressed: state.busy ? null : _viewSubmittedProfile,
                icon: const Icon(Icons.visibility_outlined, size: 20),
                label: const Text('View submitted profile'),
              ),
              const SizedBox(height: 12),
            ],
            OutlinedButton.icon(
              key: const Key('view-kyc-history'),
              onPressed: () => context.go('/kyc/history'),
              icon: const Icon(Icons.history, size: 20),
              label: const Text('Submission history'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('refresh-status'),
              onPressed: state.busy
                  ? null
                  : () => context.read<KycCubit>().load(),
              icon: const Icon(Icons.refresh, size: 20),
              label: const Text('Refresh status'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.go('/'),
              child: const Text('Back to home'),
            ),
          ],
        ),
      );
    },
  );
}
