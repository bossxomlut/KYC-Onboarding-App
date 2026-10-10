import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../kyc/domain/entities/kyc_profile.dart';
import '../../domain/entities/kyc_history.dart';

String historyDate(DateTime? value) => value == null
    ? 'Date unavailable'
    : DateFormat('d MMM yyyy, HH:mm').format(value.toLocal());

class HistoryReviewInfo extends StatelessWidget {
  const HistoryReviewInfo({
    required this.profile,
    required this.review,
    super.key,
  });
  final KycProfile profile;
  final KycHistoryReview? review;
  @override
  Widget build(BuildContext context) {
    final decision = review;
    if (decision == null && profile.status == KycStatus.pendingReview) {
      return const Text('Awaiting review');
    }
    final reviewer = decision?.reviewer;
    final reason = decision?.reason ?? profile.rejectionReason;
    final requiredSteps = decision?.requiredSteps ?? profile.requiredSteps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (decision == null)
          const Text(
            'Review information unavailable for this historical submission.',
          )
        else ...[
          Text('Reviewed ${historyDate(decision.reviewedAt)}'),
          const SizedBox(height: 6),
          Text(
            reviewer == null
                ? 'Reviewer unavailable for this historical submission.'
                : 'Reviewer: ${reviewer.email ?? reviewer.id}${reviewer.role == null ? '' : ' (${reviewer.role!.label})'}',
          ),
        ],
        if (reason != null && reason.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(reason, style: Theme.of(context).textTheme.bodyLarge),
        ],
        if (requiredSteps.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Requested updates: ${requiredSteps.map((step) => step.label).join(', ')}',
          ),
        ],
      ],
    );
  }
}
