import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/domain/result.dart';

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
        tooltip: 'Go home',
        onPressed: () => context.go('/'),
        icon: const Icon(Icons.home_outlined),
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (busy) const LinearProgressIndicator(),
            if (revalidating)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Checking account access and refreshing information…',
                ),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      error!.message,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
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
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(message!, key: const Key('access-message')),
              ),
            ...children,
          ],
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
