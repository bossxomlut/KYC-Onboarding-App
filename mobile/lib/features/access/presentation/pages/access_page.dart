import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../auth/domain/entities/user.dart';
import '../../domain/entities/access_entities.dart';
import '../bloc/access_cubit.dart';
import '../widgets/access_scaffold.dart';

class AccessPage extends StatefulWidget {
  const AccessPage({
    required this.user,
    required this.onUserUpdated,
    super.key,
  });
  final User user;
  final ValueChanged<User> onUserUpdated;
  @override
  State<AccessPage> createState() => _AccessPageState();
}

class _AccessPageState extends State<AccessPage> {
  final _reason = TextEditingController();
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocConsumer<AccessCubit, AccessState>(
    listenWhen: (before, after) =>
        before.user != after.user && after.user != null,
    listener: (_, state) => widget.onUserUpdated(state.user!),
    builder: (context, state) {
      final user = state.user ?? widget.user;
      final request = state.request;
      return AccessScaffold(
        title: 'Account access',
        busy: state.busy,
        error: state.error,
        message: state.message,
        onRefresh: () => context.read<AccessCubit>().loadAccess(),
        children: [
          Text(user.email, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Text(
            'Current role: ${user.role.label}',
            key: const Key('current-role'),
          ),
          const SizedBox(height: 12),
          const Text(
            'The super admin grants or removes reviewer access. Refresh here after your request is processed.',
          ),
          if (user.canManageUsers) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => context.go('/admin'),
              icon: const Icon(Icons.manage_accounts_outlined),
              label: const Text('Manage accounts'),
            ),
          ],
          if (user.canReview) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => context.go('/reviews'),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Review profiles'),
            ),
          ],
          if (request != null) ...[
            const SizedBox(height: 24),
            Text(
              'Request status: ${request.status.name}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(request.reason),
            if (request.decisionReason != null) ...[
              const SizedBox(height: 8),
              Text('Admin response: ${request.decisionReason}'),
            ],
          ],
          if (!user.canReview &&
              request?.status != RoleRequestStatus.pending) ...[
            const SizedBox(height: 24),
            Text(
              'Request reviewer access',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('request-reason'),
              controller: _reason,
              enabled: !state.busy,
              maxLines: 4,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: 'Why do you need review access?',
                helperText: '10–1000 characters',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('request-reviewer'),
              onPressed: state.busy
                  ? null
                  : () async {
                      if (await context.read<AccessCubit>().requestReviewer(
                            _reason.text,
                          ) &&
                          mounted) {
                        _reason.clear();
                      }
                    },
              child: const Text('Send request'),
            ),
          ],
        ],
      );
    },
  );
}
