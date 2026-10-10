import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Keeps feature-route system Back within the app, even without route history.
class BackToHomeScope extends StatelessWidget {
  const BackToHomeScope({required this.child, this.enabled = true, super.key});

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: !enabled,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && enabled) context.go('/');
    },
    child: child,
  );
}
