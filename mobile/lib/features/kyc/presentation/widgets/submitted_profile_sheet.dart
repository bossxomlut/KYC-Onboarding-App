import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../bloc/kyc_cubit.dart';
import 'kyc_profile_summary.dart';
import 'kyc_scaffold.dart';

class SubmittedProfileSheet extends StatefulWidget {
  const SubmittedProfileSheet({super.key});

  @override
  State<SubmittedProfileSheet> createState() => _SubmittedProfileSheetState();
}

class _SubmittedProfileSheetState extends State<SubmittedProfileSheet> {
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
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: .9,
    child: SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Submitted profile',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  key: const Key('close-submitted-profile'),
                  tooltip: 'Close submitted profile',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: BlocBuilder<KycCubit, KycState>(
              builder: (context, state) {
                final submittedAt = state.profile?.submittedAt;
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'The details and photos you sent for verification.',
                      ),
                      if (submittedAt != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Submitted on ${DateFormat('d MMMM yyyy, HH:mm', 'en_US').format(submittedAt.toLocal())}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 20),
                      KycError(
                        retryKey: const Key('retry-submitted-media'),
                        onRetry: state.errorSource == KycErrorSource.operation
                            ? null
                            : () => context.read<KycCubit>().retryRead(),
                      ),
                      if (state.busy) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 16),
                      ],
                      KycProfileSummary(
                        profile: state.profile,
                        media: state.reviewMedia,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
