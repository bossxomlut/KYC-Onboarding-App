import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// A mounted page can already be leaving while its async action completes.
bool isCurrentRoute(BuildContext context) =>
    context.mounted &&
    GoRouterState.of(context).uri ==
        GoRouter.of(context).routeInformationProvider.value.uri;
