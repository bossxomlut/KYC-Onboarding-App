import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/navigation/current_route.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/kyc_profile.dart';
import '../bloc/kyc_cubit.dart';
import '../widgets/kyc_profile_summary.dart';
import '../widgets/kyc_scaffold.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key});
  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  late final KycCubit _cubit;
  @override
  void initState() {
    super.initState();
    _cubit = context.read<KycCubit>()..retainReviewMediaView();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _cubit.loadReviewMedia();
    });
  }

  @override
  void dispose() {
    _cubit.releaseReviewMediaView();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<KycCubit, KycState>(
    builder: (context, state) {
      final profile = state.profile;
      final verificationStatus = profile?.verification?.status;
      final canRunChecks =
          (profile?.canEdit ?? false) &&
          (verificationStatus == VerificationStatus.notStarted ||
              verificationStatus == VerificationStatus.failed);
      final processingDisclosure = profile?.verification?.provider == 'local'
          ? 'Your document and selfie are processed on the app server when you run identity checks. '
                'No external identity service is used.'
          : 'Your document and selfie are sent to AWS when you run identity checks.';
      return KycScaffold(
        title: 'Review & submit',
        signatureHeader: const KycSignatureIntro(
          currentStep: 4,
          title: 'Everything look right?',
          description:
              'Check your details and photos before sending your profile for verification.',
        ),
        bottomBar: FilledButton(
          key: const Key('submit-kyc'),
          onPressed: state.busy || !(profile?.canSubmit ?? false)
              ? null
              : () async {
                  final cubit = context.read<KycCubit>();
                  final success = await cubit.submit();
                  if (success && context.mounted && isCurrentRoute(context)) {
                    context.pushReplacement('/kyc/status');
                  }
                },
          child: const Text('Submit for verification'),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KycError(
              onRetry: state.errorSource == KycErrorSource.operation
                  ? null
                  : () => context.read<KycCubit>().retryRead(),
            ),
            if (state.busy) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 16),
            ],
            KycProfileSummary(
              profile: profile,
              media: state.reviewMedia,
              onEdit: state.busy
                  ? null
                  : (step) => context.pushReplacement(step.routePath),
            ),
            if (canRunChecks) ...[
              const SizedBox(height: 16),
              Text(
                '$processingDisclosure '
                'Review any extracted details before submitting. These checks do not '
                'include liveness detection; a reviewer makes the final decision.',
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('run-identity-checks'),
                onPressed:
                    state.busy ||
                        profile?.document == null ||
                        profile?.selfie == null ||
                        state.pendingCaptures.isNotEmpty
                    ? null
                    : () => context.read<KycCubit>().verifyIdentity(),
                icon: const Icon(Icons.fact_check_outlined),
                label: Text(
                  state.operation == KycOperation.verifying
                      ? 'Running identity checks…'
                      : verificationStatus == VerificationStatus.failed
                      ? 'Retry identity checks'
                      : 'Run identity checks',
                ),
              ),
            ],
            const SizedBox(height: 24),
            Text(
              'By submitting, you confirm that these details are accurate. You can follow the review result from your home screen.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.muted,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    },
  );
}
