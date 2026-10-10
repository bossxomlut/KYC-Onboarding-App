import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../kyc/presentation/widgets/kyc_profile_summary.dart';
import '../bloc/kyc_history_cubit.dart';
import 'history_review_info.dart';

class HistoryDetailSheet extends StatelessWidget {
  const HistoryDetailSheet({super.key});
  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: .92,
    child: SafeArea(
      child: BlocBuilder<KycHistoryCubit, KycHistoryState>(
        builder: (context, state) {
          final submission = state.selectedSubmission;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        submission == null
                            ? 'Submission history'
                            : 'Submission #${submission.version}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      key: const Key('history-detail-close'),
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: submission == null
                      ? Text(
                          state.error?.message ??
                              'This submission is no longer available.',
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Submitted ${historyDate(submission.profile.submittedAt)}',
                            ),
                            const SizedBox(height: 16),
                            HistoryReviewInfo(
                              profile: submission.profile,
                              review: submission.review,
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'Information and photos saved for this submission.',
                            ),
                            const SizedBox(height: 20),
                            if (state.mediaLoading)
                              const LinearProgressIndicator(),
                            if (state.mediaError != null) ...[
                              Text(
                                state.mediaError!.message,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                  key: const Key('history-media-retry'),
                                  onPressed: state.mediaLoading
                                      ? null
                                      : context
                                            .read<KycHistoryCubit>()
                                            .retryMedia,
                                  child: const Text('Retry photos'),
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            KycProfileSummary(
                              profile: submission.profile,
                              media: state.media,
                            ),
                          ],
                        ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
