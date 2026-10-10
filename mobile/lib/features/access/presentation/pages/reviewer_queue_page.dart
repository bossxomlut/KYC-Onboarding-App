import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../domain/entities/access_entities.dart';
import '../bloc/access_cubit.dart';
import '../widgets/access_scaffold.dart';

class ReviewerQueuePage extends StatelessWidget {
  const ReviewerQueuePage({required this.actorId, super.key});
  final String actorId;
  @override
  Widget build(BuildContext context) => BlocBuilder<AccessCubit, AccessState>(
    builder: (context, state) {
      final queue = state.queue;
      final cubit = context.read<AccessCubit>();
      return AccessScaffold(
        title: 'Review profiles',
        busy: state.busy,
        error: state.error,
        message: state.message,
        onRefresh: () => cubit.loadQueue(),
        children: [
          const Text(
            'Check the personal details, identity document and selfie before deciding. You cannot review your own profile.',
          ),
          const SizedBox(height: 20),
          if (queue != null && queue.items.isEmpty)
            const Text(
              'No profiles are waiting for review.',
              key: Key('empty-review-queue'),
            ),
          for (final profile in queue?.items ?? <ReviewSummary>[])
            Card(
              child: ListTile(
                title: Text(profile.email),
                subtitle: Text(
                  profile.submittedAt == null
                      ? 'Pending review'
                      : 'Submitted ${profile.submittedAt!.toLocal().toString().split('.').first}',
                ),
                trailing: const Icon(Icons.chevron_right),
                enabled: profile.userId != actorId && !state.busy,
                onTap: () => context.go(
                  '/reviews/${Uri.encodeComponent(profile.userId)}',
                ),
              ),
            ),
          if (queue != null)
            AccessPagination(
              offset: queue.offset,
              count: queue.items.length,
              total: queue.total,
              busy: state.busy,
              onPage: (offset) => cubit.loadQueue(offset: offset),
            ),
        ],
      );
    },
  );
}
