import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../domain/entities/kyc_profile.dart';
import '../bloc/kyc_cubit.dart';
import '../widgets/kyc_scaffold.dart';

class VerificationPage extends StatefulWidget {
  const VerificationPage({super.key});
  @override
  State<VerificationPage> createState() => _VerificationPageState();
}

class _VerificationPageState extends State<VerificationPage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<KycCubit>().load();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<KycCubit>().load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<KycCubit, KycState>(
    builder: (context, state) {
      final profile = state.profile;
      final status = profile?.status;
      final rejected = status == KycStatus.rejected;
      final verified = status == KycStatus.verified;
      return KycScaffold(
        title: 'Verification status',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KycIntro(
              step: 'Verification result',
              title: profile?.status.label ?? 'Loading your status…',
              description: verified
                  ? 'Your identity has been verified. You’re all set.'
                  : rejected
                  ? 'A few updates are needed before we can verify your identity.'
                  : status == KycStatus.pendingReview
                  ? 'Your profile has been submitted. Refresh here to see the latest review result.'
                  : 'Continue your verification to complete the remaining steps.',
              icon: verified
                  ? Icons.verified_outlined
                  : rejected
                  ? Icons.error_outline
                  : Icons.hourglass_top_outlined,
            ),
            KycError(onRetry: () => context.read<KycCubit>().load()),
            if (state.busy) const LinearProgressIndicator(),
            if (rejected) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Why it needs an update',
                        style: Theme.of(context).textTheme.titleMedium,
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
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('resubmit-kyc'),
                onPressed: state.busy
                    ? null
                    : () async {
                        final cubit = context.read<KycCubit>();
                        final success = await cubit.resubmit();
                        if (success && context.mounted) {
                          context.go(cubit.state.profile!.nextStep.routePath);
                        }
                      },
                child: const Text('Update and resubmit'),
              ),
            ],
            const SizedBox(height: 20),
            OutlinedButton.icon(
              key: const Key('refresh-status'),
              onPressed: state.busy
                  ? null
                  : () => context.read<KycCubit>().load(),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh status'),
            ),
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
