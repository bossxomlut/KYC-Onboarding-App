import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/navigation/back_navigation.dart';
import '../../../kyc/presentation/widgets/kyc_status_badge.dart';
import '../../domain/entities/kyc_history.dart';
import '../bloc/kyc_history_cubit.dart';
import '../widgets/history_detail_sheet.dart';
import '../widgets/history_review_info.dart';

class KycHistoryPage extends StatefulWidget {
  const KycHistoryPage({this.reviewerUserId, super.key});
  final String? reviewerUserId;
  @override
  State<KycHistoryPage> createState() => _KycHistoryPageState();
}

class _KycHistoryPageState extends State<KycHistoryPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          context.read<KycHistoryCubit>().load(
            reviewerUserId: widget.reviewerUserId,
          ),
        );
      }
    });
  }

  Future<void> _open(KycHistorySubmission submission) async {
    final cubit = context.read<KycHistoryCubit>();
    unawaited(cubit.select(submission));
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: HistoryDetailSheet(
          showVerification: widget.reviewerUserId != null,
        ),
      ),
    );
    cubit.clearSelection();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<KycHistoryCubit, KycHistoryState>(
    builder: (context, state) {
      final cubit = context.read<KycHistoryCubit>();
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Submission history',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          leading: IconButton(
            tooltip: 'Back',
            onPressed: () => popOrGo(context),
            icon: const Icon(Icons.arrow_back),
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh history',
              onPressed: state.loading || state.loadingMore || state.refreshing
                  ? null
                  : cubit.refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Each submission keeps the information, photos and review result from that round.',
                    ),
                    const SizedBox(height: 24),
                    if (state.loading)
                      const Center(child: CircularProgressIndicator()),
                    if (state.refreshing) const LinearProgressIndicator(),
                    if (state.refreshError != null) ...[
                      Text(state.refreshError!.message),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          key: const Key('history-refresh-retry'),
                          onPressed: state.refreshing ? null : cubit.refresh,
                          child: const Text('Retry'),
                        ),
                      ),
                    ],
                    if (state.error != null) ...[
                      Text(
                        state.error!.message,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          key: const Key('history-list-retry'),
                          onPressed: state.loading || state.loadingMore
                              ? null
                              : state.submissions.isEmpty
                              ? cubit.load
                              : cubit.loadMore,
                          child: const Text('Retry'),
                        ),
                      ),
                    ],
                    if (!state.loading &&
                        state.error == null &&
                        state.submissions.isEmpty)
                      const Text('No submissions yet.'),
                    for (final submission in state.submissions)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            key: Key('history-submission-${submission.id}'),
                            onTap: () => _open(submission),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Submission #${submission.version}',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleLarge,
                                        ),
                                      ),
                                      const Icon(Icons.chevron_right),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Submitted ${historyDate(submission.profile.submittedAt)}',
                                  ),
                                  const SizedBox(height: 16),
                                  KycStatusBadge(
                                    status: submission.profile.status,
                                  ),
                                  const SizedBox(height: 16),
                                  HistoryReviewInfo(
                                    profile: submission.profile,
                                    review: submission.review,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (state.hasMore)
                      OutlinedButton(
                        key: const Key('history-load-more'),
                        onPressed: state.loadingMore ? null : cubit.loadMore,
                        child: Text(
                          state.loadingMore ? 'Loading…' : 'Load more',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
