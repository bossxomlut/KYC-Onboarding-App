import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// A popped page can stay mounted while its exit animation/action completes.
bool isCurrentRoute(BuildContext context) {
  if (!context.mounted || ModalRoute.of(context)?.isActive != true) {
    return false;
  }
  final page = GoRouterState.of(context);
  final current = GoRouter.of(context).state;
  return page.pageKey == current.pageKey && page.uri == current.uri;
}
