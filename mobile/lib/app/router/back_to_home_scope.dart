import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Allows normal Back, with Home as the fallback for direct feature entry.
class BackToHomeScope extends StatelessWidget {
  const BackToHomeScope({required this.child, this.enabled = true, super.key});

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: !enabled || context.canPop(),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && enabled) context.go('/');
    },
    child: child,
  );
}
