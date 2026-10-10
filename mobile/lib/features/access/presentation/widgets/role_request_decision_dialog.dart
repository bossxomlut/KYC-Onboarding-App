import 'package:flutter/material.dart';
import '../../domain/entities/access_entities.dart';

class RoleRequestDecisionDialog extends StatefulWidget {
  const RoleRequestDecisionDialog({
    required this.request,
    required this.decision,
    super.key,
  });
  final RoleRequest request;
  final RoleRequestStatus decision;
  @override
  State<RoleRequestDecisionDialog> createState() =>
      _RoleRequestDecisionDialogState();
}

class _RoleRequestDecisionDialogState extends State<RoleRequestDecisionDialog> {
  final _reason = TextEditingController();
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      '${widget.decision == RoleRequestStatus.approved ? 'Approve' : 'Reject'} access request?',
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.request.email),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            maxLength: 1000,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Response (optional)'),
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
        onPressed: () => Navigator.pop(context, _reason.text.trim()),
        child: const Text('Confirm'),
      ),
    ],
  );
}
