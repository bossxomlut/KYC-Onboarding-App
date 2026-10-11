import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/navigation/current_route.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../kyc/domain/entities/kyc_profile.dart';
import '../../../kyc/presentation/widgets/kyc_status_badge.dart';
import '../../domain/entities/access_entities.dart';
import '../bloc/access_cubit.dart';
import '../widgets/access_scaffold.dart';

class ReviewerQueuePage extends StatefulWidget {
  const ReviewerQueuePage({required this.actorId, super.key});
  final String actorId;

  @override
  State<ReviewerQueuePage> createState() => _ReviewerQueuePageState();
}

class _ReviewerQueuePageState extends State<ReviewerQueuePage> {
  final _search = TextEditingController();
  Timer? _searchDebounce;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _search.text = context.read<AccessCubit>().state.reviewSearch;
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _loadQueue({ReviewFilter? filter, int? offset}) {
    _searchDebounce?.cancel();
    unawaited(
      context.read<AccessCubit>().loadQueue(
        offset: offset,
        filter: filter,
        search: _search.text,
      ),
    );
  }

  void _scheduleSearch(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _loadQueue();
    });
  }

  void _clearSearch() {
    _search.clear();
    _loadQueue();
  }

  String _emptyMessage(AccessState state) {
    if (state.reviewSearch.isNotEmpty) {
      return 'No profiles match your search.';
    }
    return switch (state.reviewFilter) {
      ReviewFilter.pending => 'No profiles are waiting for review.',
      ReviewFilter.approved => 'No approved profiles.',
      ReviewFilter.rejected => 'No rejected profiles.',
      ReviewFilter.all => 'No submitted profiles.',
    };
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<AccessCubit, AccessState>(
    builder: (context, state) {
      final queue = state.queue;
      return AccessScaffold(
        title: 'Review profiles',
        busy: state.busy,
        revalidating: state.needsRevalidation,
        error: state.error,
        message: state.message,
        onRefresh: _loadQueue,
        header: [
          const Text(
            'Find submitted profiles by email or review status. Check the personal details, identity document and selfie before deciding. You cannot review your own profile.',
          ),
          const SizedBox(height: 20),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _search,
            builder: (context, value, _) => TextField(
              key: const Key('review-search'),
              controller: _search,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.search,
              autocorrect: false,
              maxLength: 254,
              decoration: InputDecoration(
                labelText: 'Search by email',
                prefixIcon: const Icon(Icons.search),
                counterText: '',
                suffixIcon: value.text.isEmpty
                    ? null
                    : IconButton(
                        key: const Key('review-search-clear'),
                        tooltip: 'Clear search',
                        onPressed: _clearSearch,
                        icon: const Icon(Icons.clear),
                      ),
              ),
              onChanged: _scheduleSearch,
              onSubmitted: (_) => _loadQueue(),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final filter in [
                ReviewFilter.pending,
                ReviewFilter.approved,
                ReviewFilter.rejected,
                ReviewFilter.all,
              ])
                ChoiceChip(
                  key: Key('review-filter-${filter.name}'),
                  label: Text(switch (filter) {
                    ReviewFilter.pending => 'Pending review',
                    ReviewFilter.approved => 'Approved',
                    ReviewFilter.rejected => 'Rejected',
                    ReviewFilter.all => 'All',
                  }),
                  selected: state.reviewFilter == filter,
                  onSelected: (_) => _loadQueue(filter: filter),
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        children: [
          if (queue != null && queue.items.isEmpty && !state.busy)
            Text(_emptyMessage(state), key: const Key('empty-review-queue')),
          for (final profile in queue?.items ?? <ReviewSummary>[])
            Card(
              key: ValueKey('review-profile-${profile.userId}'),
              margin: const EdgeInsets.only(bottom: AppTheme.cardSpacing),
              child: ListTile(
                title: Text(profile.email),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (profile.submittedAt != null) ...[
                      Text(
                        'Submitted ${profile.submittedAt!.toLocal().toString().split('.').first}',
                      ),
                      const SizedBox(height: 6),
                    ],
                    KycStatusBadge(status: profile.status, compact: true),
                  ],
                ),
                trailing: const Icon(Icons.chevron_right),
                enabled: profile.userId != widget.actorId && !state.busy,
                onTap: () async {
                  final target =
                      '/reviews/${Uri.encodeComponent(profile.userId)}';
                  await context.push<void>(
                    profile.status == KycStatus.pendingReview
                        ? target
                        : '$target/history?from=queue',
                  );
                  if (!context.mounted || !isCurrentRoute(context)) return;
                  _loadQueue();
                },
              ),
            ),
          if (queue != null)
            AccessPagination(
              offset: queue.offset,
              count: queue.items.length,
              total: queue.total,
              busy: state.busy,
              onPage: (offset) => _loadQueue(offset: offset),
            ),
        ],
      );
    },
  );
}
