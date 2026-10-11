import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/navigation/current_route.dart';

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
  GoRouter? _router;
  bool _needsRefresh = false;
  bool _refreshing = false;
  bool _routeRefreshScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = ForegroundRefreshScope.of(context);
    if (_controller != controller) {
      _controller?.removeListener(_changed);
      _controller = controller..addListener(_changed);
    }
    final router = GoRouter.of(context);
    if (_router != router) {
      _router?.routerDelegate.removeListener(_routeChanged);
      _router = router..routerDelegate.addListener(_routeChanged);
    }
  }

  bool get _isCurrent =>
      _router?.state.uri.path == widget.location && isCurrentRoute(context);

  void _changed() {
    if (!mounted) return;
    if (_controller!.isBackgrounded) {
      // Pushed pages stay mounted. Their data must be revalidated before they
      // become visible again, even if another page handles this resume.
      _needsRefresh = true;
      widget.onBackground?.call(context);
    } else {
      _refreshIfCurrent(force: true);
    }
  }

  void _routeChanged() {
    if (!mounted || !_needsRefresh || _routeRefreshScheduled) return;
    _routeRefreshScheduled = true;
    // Let Router report the popped stack before session revalidation emits
    // changes that can make go_router reparse that stack.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _routeRefreshScheduled = false;
      _refreshIfCurrent();
    });
  }

  void _refreshIfCurrent({bool force = false}) {
    if (!mounted ||
        _controller!.isBackgrounded ||
        !_isCurrent ||
        _refreshing ||
        (!force && !_needsRefresh)) {
      return;
    }
    _refreshing = true;
    unawaited(_refresh(_controller!.generation));
  }

  Future<void> _refresh(int generation) async {
    try {
      await widget.onResume(context);
    } finally {
      _refreshing = false;
      if (mounted) {
        final controller = _controller!;
        if (generation == controller.generation &&
            !controller.isBackgrounded &&
            _isCurrent) {
          _needsRefresh = false;
        } else if (generation != controller.generation) {
          // A newer background cycle may have resumed during the old check.
          _refreshIfCurrent();
        }
      }
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_changed);
    _router?.routerDelegate.removeListener(_routeChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
