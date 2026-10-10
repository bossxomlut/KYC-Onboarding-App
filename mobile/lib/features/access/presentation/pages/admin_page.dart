import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../auth/domain/entities/user.dart';
import '../../domain/entities/access_entities.dart';
import '../bloc/access_cubit.dart';
import '../widgets/access_scaffold.dart';
import '../widgets/role_request_decision_dialog.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  UserRole _newRole = UserRole.user;
  bool _showPassword = false;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<AccessCubit, AccessState>(
    builder: (context, state) {
      final cubit = context.read<AccessCubit>();
      final users = state.users;
      final requests = state.requests;
      return AccessScaffold(
        title: 'Manage accounts',
        busy: state.busy,
        error: state.error,
        message: state.message,
        onRefresh: () => cubit.loadAdmin(),
        children: [
          const Text(
            'Only the super admin can create accounts or change reviewer access.',
          ),
          const SizedBox(height: 16),
          ExpansionTile(
            title: const Text('Create account'),
            leading: const Icon(Icons.person_add_outlined),
            childrenPadding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              TextField(
                key: const Key('admin-create-email'),
                controller: _email,
                enabled: !state.busy,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('admin-create-password'),
                controller: _password,
                enabled: !state.busy,
                obscureText: !_showPassword,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Initial password',
                  helperText: '12–128 characters: uppercase, lowercase, number',
                  helperMaxLines: 2,
                  suffixIcon: IconButton(
                    tooltip: _showPassword ? 'Hide password' : 'Show password',
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                    icon: Icon(
                      _showPassword ? Icons.visibility_off : Icons.visibility,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<UserRole>(
                initialValue: _newRole,
                decoration: const InputDecoration(labelText: 'Role'),
                items: [
                  for (final role in [UserRole.user, UserRole.reviewer])
                    DropdownMenuItem(value: role, child: Text(role.label)),
                ],
                onChanged: state.busy
                    ? null
                    : (role) => setState(() => _newRole = role!),
              ),
              const SizedBox(height: 12),
              const Text(
                'An OTP will be emailed to this address. The account must verify its email before signing in.',
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('admin-create-account'),
                onPressed: state.busy
                    ? null
                    : () async {
                        if (await cubit.createUser(
                              _email.text,
                              _password.text,
                              _newRole,
                            ) &&
                            mounted) {
                          _email.clear();
                          _password.clear();
                        }
                      },
                child: const Text('Create account'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Pending access requests',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (requests != null && requests.items.isEmpty)
            const Text('No pending requests.'),
          for (final request in requests?.items ?? <RoleRequest>[])
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      request.email,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(request.reason),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      children: [
                        FilledButton(
                          onPressed: state.busy
                              ? null
                              : () => _decideRequest(
                                  context,
                                  request,
                                  RoleRequestStatus.approved,
                                ),
                          child: const Text('Approve access'),
                        ),
                        OutlinedButton(
                          onPressed: state.busy
                              ? null
                              : () => _decideRequest(
                                  context,
                                  request,
                                  RoleRequestStatus.rejected,
                                ),
                          child: const Text('Reject request'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (requests != null)
            AccessPagination(
              offset: requests.offset,
              count: requests.items.length,
              total: requests.total,
              busy: state.busy,
              onPage: (offset) => cubit.loadAdmin(
                offset: users?.offset ?? 0,
                requestOffset: offset,
              ),
            ),
          const SizedBox(height: 24),
          Text('Accounts', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (users != null && users.items.isEmpty)
            const Text('No accounts found.'),
          for (final managed in users?.items ?? <ManagedUser>[])
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      managed.user.email,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${managed.user.role.label} • ${managed.user.emailVerified ? 'Email verified' : 'Awaiting email verification'}',
                    ),
                    if (managed.user.role == UserRole.superAdmin)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('Protected bootstrap account'),
                      )
                    else ...[
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: state.busy
                            ? null
                            : () => _changeRole(context, managed.user),
                        child: Text(
                          managed.user.role == UserRole.reviewer
                              ? 'Remove reviewer access'
                              : 'Grant reviewer access',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (users != null)
            AccessPagination(
              offset: users.offset,
              count: users.items.length,
              total: users.total,
              busy: state.busy,
              onPage: (offset) => cubit.loadAdmin(
                offset: offset,
                requestOffset: requests?.offset ?? 0,
              ),
            ),
        ],
      );
    },
  );
  Future<void> _changeRole(BuildContext context, User user) async {
    final next = user.role == UserRole.reviewer
        ? UserRole.user
        : UserRole.reviewer;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Set role to ${next.label}?'),
        content: Text('Update access for ${user.email}.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Update role'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<AccessCubit>().changeRole(user.id, next);
    }
  }

  Future<void> _decideRequest(
    BuildContext context,
    RoleRequest request,
    RoleRequestStatus decision,
  ) async {
    final response = await showDialog<String>(
      context: context,
      builder: (_) =>
          RoleRequestDecisionDialog(request: request, decision: decision),
    );
    if (response != null && context.mounted) {
      await context.read<AccessCubit>().decideRequest(
        request.id,
        decision,
        reason: response,
      );
    }
  }
}
