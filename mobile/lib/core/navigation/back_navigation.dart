import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Returns to the previous page, with a destination for direct/deep-link entry.
void popOrGo(BuildContext context, {String fallback = '/'}) {
  final router = GoRouter.of(context);
  if (router.canPop()) {
    router.pop();
  } else {
    router.go(fallback);
  }
}
