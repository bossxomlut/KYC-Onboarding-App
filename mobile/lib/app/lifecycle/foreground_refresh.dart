import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// One app-owned lifecycle source; route providers retain their own state.
class ForegroundRefreshController extends ChangeNotifier {
  bool _backgrounded = false;
  int _generation = 0;
  bool get isBackgrounded => _backgrounded;
  int get generation => _generation;

  void handle(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      if (_backgrounded) return;
      _backgrounded = true;
      _generation++;
      notifyListeners();
    } else if (state == AppLifecycleState.resumed && _backgrounded) {
      _backgrounded = false;
      notifyListeners();
    }
  }

  void retry() {
    if (!_backgrounded) notifyListeners();
  }
}

class ForegroundRefreshScope extends InheritedWidget {
  const ForegroundRefreshScope({
    required this.controller,
    required super.child,
    super.key,
  });
  final ForegroundRefreshController controller;
  static ForegroundRefreshController of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ForegroundRefreshScope>()!
      .controller;
  @override
  bool updateShouldNotify(ForegroundRefreshScope oldWidget) =>
      oldWidget.controller != controller;
}

class RouteForegroundRefresh extends StatefulWidget {
  const RouteForegroundRefresh({
    required this.location,
    required this.onResume,
    required this.child,
    this.onBackground,
    super.key,
  });
  final String location;
  final Future<void> Function(BuildContext) onResume;
  final void Function(BuildContext)? onBackground;
  final Widget child;
  @override
  State<RouteForegroundRefresh> createState() => _RouteForegroundRefreshState();
}

class _RouteForegroundRefreshState extends State<RouteForegroundRefresh> {
  ForegroundRefreshController? _controller;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = ForegroundRefreshScope.of(context);
    if (_controller == controller) return;
    _controller?.removeListener(_changed);
    _controller = controller..addListener(_changed);
  }

  void _changed() {
    if (!mounted ||
        GoRouter.of(context).routeInformationProvider.value.uri.path !=
            widget.location) {
      return;
    }
    if (_controller!.isBackgrounded) {
      widget.onBackground?.call(context);
    } else {
      unawaited(widget.onResume(context));
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
