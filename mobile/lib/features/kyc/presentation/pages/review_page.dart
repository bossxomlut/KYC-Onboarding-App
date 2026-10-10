import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../bloc/kyc_cubit.dart';
import '../widgets/kyc_profile_summary.dart';
import '../widgets/kyc_scaffold.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key});
  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<KycCubit>().loadReviewMedia();
    });
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<KycCubit, KycState>(
    builder: (context, state) {
      final profile = state.profile;
      return KycScaffold(
        title: 'Review & submit',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const KycIntro(
              step: 'Step 4 of 4',
              title: 'Everything look right?',
              description:
                  'Check your details and photos before sending your profile for verification.',
              icon: Icons.fact_check_outlined,
            ),
            KycError(onRetry: () => context.read<KycCubit>().loadReviewMedia()),
            if (state.busy) const LinearProgressIndicator(),
            const SizedBox(height: 16),
            KycProfileSummary(
              profile: profile,
              media: state.reviewMedia,
              onEdit: (step) => context.go(step.routePath),
            ),
            const SizedBox(height: 24),
            const Text(
              'By submitting, you confirm that these details are accurate. You can follow the review result from your home screen.',
            ),
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('submit-kyc'),
              onPressed: state.busy || !(profile?.canSubmit ?? false)
                  ? null
                  : () async {
                      final cubit = context.read<KycCubit>();
                      final success = await cubit.submit();
                      if (success && context.mounted) {
                        context.go('/kyc/status');
                      }
                    },
              child: const Text('Submit for verification'),
            ),
          ],
        ),
      );
    },
  );
}
