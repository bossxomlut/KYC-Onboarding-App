import 'package:flutter/material.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/navigation/back_navigation.dart';
import '../../../../core/theme/app_theme.dart';

class AccessScaffold extends StatelessWidget {
  const AccessScaffold({
    required this.title,
    required this.children,
    this.busy = false,
    this.revalidating = false,
    this.error,
    this.message,
    this.onRefresh,
    super.key,
  });
  final String title;
  final List<Widget> children;
  final bool busy;
  final bool revalidating;
  final AppFailure? error;
  final String? message;
  final VoidCallback? onRefresh;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      leading: IconButton(
        tooltip: 'Back',
        onPressed: () => popOrGo(context),
        icon: const Icon(Icons.arrow_back),
      ),
      actions: [
        if (onRefresh != null)
          IconButton(
            tooltip: 'Refresh',
            onPressed: busy ? null : onRefresh,
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
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (busy) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 16),
                ],
                if (revalidating)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Checking account access and refreshing information…',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: AppTheme.muted),
                    ),
                  ),
                if (error != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(AppTheme.panelRadius),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          error!.message,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                          ),
                        ),
                        if (onRefresh != null)
                          TextButton(
                            onPressed: busy ? null : onRefresh,
                            child: const Text('Retry'),
                          ),
                      ],
                    ),
                  ),
                if (message != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.mint,
                      border: Border.all(color: AppTheme.border),
                      borderRadius: BorderRadius.circular(AppTheme.panelRadius),
                    ),
                    child: Text(message!, key: const Key('access-message')),
                  ),
                ...children,
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class AccessPagination extends StatelessWidget {
  const AccessPagination({
    required this.offset,
    required this.count,
    required this.total,
    required this.onPage,
    this.busy = false,
    super.key,
  });
  final int offset;
  final int count;
  final int total;
  final bool busy;
  final ValueChanged<int> onPage;
  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 12,
    children: [
      OutlinedButton(
        onPressed: busy || offset == 0
            ? null
            : () => onPage((offset - 50).clamp(0, total)),
        child: const Text('Previous'),
      ),
      Text(
        total == 0 ? '0 items' : '${offset + 1}–${offset + count} of $total',
      ),
      OutlinedButton(
        onPressed: busy || offset + count >= total
            ? null
            : () => onPage(offset + count),
        child: const Text('Next'),
      ),
    ],
  );
}
