import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
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
      final appearance = profile == null
          ? null
          : KycStatusAppearance.forStatus(profile.status);
      return KycScaffold(
        title: 'Your verification',
        actions: [
          IconButton(
            key: const Key('account-access'),
            tooltip: 'Account access',
            onPressed: () => context.go('/access'),
            icon: const Icon(Icons.manage_accounts_outlined),
          ),
          IconButton(
            key: const Key('logout'),
            tooltip: 'Sign out',
            onPressed: state.busy ? null : onLogout,
            icon: const Icon(Icons.logout),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const KycIntro(
              step: 'Welcome',
              title: 'A secure start.',
              description:
                  'Verify your identity in a few simple steps. Your saved progress is ready whenever you return.',
              icon: Icons.verified_user_outlined,
            ),
            Text(email, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            if (canReview)
              OutlinedButton.icon(
                key: const Key('review-profiles'),
                onPressed: () => context.go('/reviews'),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Review profiles'),
              ),
            const SizedBox(height: 20),
            KycError(onRetry: () => context.read<KycCubit>().load()),
            if (state.busy && profile == null)
              const Center(child: CircularProgressIndicator()),
            if (profile != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'VERIFICATION STATUS',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 10),
                      KycStatusBadge(
                        status: profile.status,
                        labelKey: const Key('kyc-status'),
                      ),
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                        color: appearance!.foreground,
                        backgroundColor: appearance.background,
                        borderRadius: BorderRadius.circular(8),
                        minHeight: 6,
                        value: profile.status == KycStatus.verified
                            ? 1
                            : profile.nextStep.index / 4,
                      ),
                      const SizedBox(height: 12),
                      Text('Next: ${profile.nextStep.label}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              for (final step in KycStep.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    step.index < profile.nextStep.index ||
                            profile.status == KycStatus.verified
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: step.index <= profile.nextStep.index
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
                  ),
                  title: Text(step.label),
                  subtitle: step == profile.nextStep
                      ? const Text('Your next step')
                      : null,
                ),
              const SizedBox(height: 24),
              if (profile.status == KycStatus.rejected) ...[
                Text(
                  profile.rejectionReason ??
                      'Please update the requested information.',
                ),
                const SizedBox(height: 8),
                Text(
                  'Required: ${profile.requiredSteps.map((step) => step.label).join(', ')}',
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
            const SizedBox(height: 16),
            const Text(
              'Your photos are stored privately. You and authorized reviewers can view them after signing in.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    },
  );
}
