import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/navigation/current_route.dart';
import '../../../kyc/domain/entities/kyc_profile.dart';
import '../../domain/entities/access_entities.dart';
import '../bloc/access_cubit.dart';
import '../widgets/access_scaffold.dart';
import '../widgets/private_review_photo.dart';

class ReviewerDetailPage extends StatelessWidget {
  const ReviewerDetailPage({
    required this.userId,
    required this.actorId,
    super.key,
  });
  final String userId;
  final String actorId;
  @override
  Widget build(BuildContext context) => BlocBuilder<AccessCubit, AccessState>(
    builder: (context, state) {
      final detail = state.detail;
      final profile = detail?.profile;
      final personal = profile?.personalDetails;
      final mediaReady =
          profile?.document != null &&
          profile?.selfie != null &&
          state.media.length == 2;
      final canDecide =
          !state.busy &&
          state.error == null &&
          profile?.status == KycStatus.pendingReview &&
          actorId != userId &&
          mediaReady;
      return AccessScaffold(
        title: 'Review identity',
        busy: state.busy,
        error: state.error,
        onRefresh: () => context.read<AccessCubit>().loadDetail(userId),
        children: [
          TextButton.icon(
            onPressed: () => context.go('/reviews'),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back to review queue'),
          ),
          if (detail != null) ...[
            Text(detail.email, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Status: ${profile!.status.label}'),
            const SizedBox(height: 20),
            Text(
              'Personal details',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (personal == null)
              const Text('Personal details unavailable.')
            else ...[
              _field('Full name', personal.fullName),
              _field('Date of birth', personal.dateOfBirth),
              _field('Nationality', personal.nationality),
              _field('Residential address', personal.address),
              _field('Document number', personal.documentNumber),
            ],
            for (final kind in MediaKind.values) ...[
              const SizedBox(height: 20),
              Text(
                kind == MediaKind.document ? 'Identity document' : 'Selfie',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (kind == MediaKind.document &&
                  profile.document?.documentType != null)
                Text(profile.document!.documentType!.label),
              const SizedBox(height: 12),
              if (state.media[kind] != null)
                PrivateReviewPhoto(
                  bytes: state.media[kind]!,
                  label: kind == MediaKind.document
                      ? 'Submitted identity document'
                      : 'Submitted selfie',
                )
              else
                SizedBox(
                  height: 80,
                  child: Center(
                    child: Text(
                      state.busy
                          ? 'Loading private image…'
                          : 'Private image unavailable. Refresh to retry.',
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 24),
            if (actorId == userId)
              const Text('You cannot review your own profile.'),
            if (!mediaReady && !state.busy)
              const Text(
                'Both private images must load before a decision can be saved.',
              ),
            FilledButton(
              key: const Key('review-approve'),
              onPressed: canDecide ? () => _approve(context) : null,
              child: const Text('Approve identity'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('review-reject'),
              onPressed: canDecide ? () => _reject(context) : null,
              child: const Text('Reject and request updates'),
            ),
          ],
        ],
      );
    },
  );
  Widget _field(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        SelectableText(value),
      ],
    ),
  );
  Future<void> _approve(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Approve this identity?'),
        content: const Text(
          'Confirm that you have checked the details, document and selfie.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final saved = await context.read<AccessCubit>().decideProfile(
      userId,
      ReviewDecision.verified,
      actorId: actorId,
    );
    if (saved && context.mounted && isCurrentRoute(context)) {
      context.go('/reviews');
    }
  }

  Future<void> _reject(BuildContext context) async {
    final result = await showDialog<_Rejection>(
      context: context,
      builder: (_) => const _RejectionDialog(),
    );
    if (result == null || !context.mounted) return;
    final saved = await context.read<AccessCubit>().decideProfile(
      userId,
      ReviewDecision.rejected,
      actorId: actorId,
      reason: result.reason,
      requiredSteps: result.steps,
    );
    if (saved && context.mounted && isCurrentRoute(context)) {
      context.go('/reviews');
    }
  }
}

class _Rejection {
  const _Rejection(this.reason, this.steps);
  final String reason;
  final List<KycStep> steps;
}

class _RejectionDialog extends StatefulWidget {
  const _RejectionDialog();
  @override
  State<_RejectionDialog> createState() => _RejectionDialogState();
}

class _RejectionDialogState extends State<_RejectionDialog> {
  final _reason = TextEditingController();
  final _steps = <KycStep>{};
  String? _error;
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Request updates'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('rejection-reason'),
            controller: _reason,
            maxLines: 3,
            maxLength: 1000,
            decoration: InputDecoration(
              labelText: 'Reason',
              helperText: '3–1000 characters',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 12),
          const Text('Which steps must the user update?'),
          for (final step in [
            KycStep.personalDetails,
            KycStep.document,
            KycStep.selfie,
          ])
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(step.label),
              value: _steps.contains(step),
              onChanged: (selected) => setState(
                () => selected == true ? _steps.add(step) : _steps.remove(step),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_reason.text.trim().length < 3 || _steps.isEmpty) {
            setState(
              () => _error = 'Give a reason and select at least one step.',
            );
            return;
          }
          Navigator.pop(
            context,
            _Rejection(_reason.text.trim(), List.unmodifiable(_steps)),
          );
        },
        child: const Text('Save rejection'),
      ),
    ],
  );
}
