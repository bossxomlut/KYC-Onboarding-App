import 'package:flutter/material.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/navigation/back_navigation.dart';
import '../../../../core/theme/app_theme.dart';

class AccessScaffold extends StatelessWidget {
  static const _contentPadding = EdgeInsets.fromLTRB(24, 20, 24, 24);

  const AccessScaffold({
    required this.title,
    required this.children,
    this.header = const [],
    this.busy = false,
    this.revalidating = false,
    this.error,
    this.message,
    this.onBack,
    this.onRefresh,
    super.key,
  });
  final String title;
  final List<Widget> children;
  final List<Widget> header;
  final bool busy;
  final bool revalidating;
  final AppFailure? error;
  final String? message;
  final VoidCallback? onBack;
  final VoidCallback? onRefresh;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      leading: IconButton(
        tooltip: 'Back',
        onPressed: onBack ?? () => popOrGo(context),
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
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              children: [
                SingleChildScrollView(
                  padding: _contentPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Status changes must not recreate focused page inputs.
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: header,
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (revalidating)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                'Checking account access and refreshing information…',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: AppTheme.muted),
                              ),
                            ),
                          if (error != null)
                            Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(
                                  AppTheme.panelRadius,
                                ),
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
                                borderRadius: BorderRadius.circular(
                                  AppTheme.panelRadius,
                                ),
                              ),
                              child: Text(
                                message!,
                                key: const Key('access-message'),
                              ),
                            ),
                        ],
                      ),
                      ConstrainedBox(
                        // Shorter results must not clamp a scrolled header.
                        constraints: BoxConstraints(
                          minHeight: header.isEmpty
                              ? 0
                              : (constraints.maxHeight -
                                        _contentPadding.vertical)
                                    .clamp(0, double.infinity),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: children,
                        ),
                      ),
                    ],
                  ),
                ),
                if (busy)
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(),
                  ),
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
