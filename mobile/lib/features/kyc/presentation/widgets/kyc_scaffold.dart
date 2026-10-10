import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../bloc/kyc_cubit.dart';

class KycScaffold extends StatelessWidget {
  const KycScaffold({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
  });
  final String title;
  final Widget child;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: actions,
          leading: (ModalRoute.of(context)?.canPop ?? false)
              ? null
              : (GoRouterState.of(context).uri.path == '/'
                  ? null
                  : IconButton(
                      tooltip: 'Home',
                      onPressed: () => context.go('/'),
                      icon: const Icon(Icons.arrow_back),
                    )),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: child,
              ),
            ),
          ),
        ),
      );
}

class KycError extends StatelessWidget {
  const KycError({super.key, this.onRetry});
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => BlocBuilder<KycCubit, KycState>(
        builder: (context, state) {
          if (state.error == null) return const SizedBox.shrink();
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.error!.message,
                  key: const Key('kyc-error'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
                if (onRetry != null)
                  TextButton(
                    onPressed: state.busy ? null : onRetry,
                    child: const Text('Retry'),
                  ),
              ],
            ),
          );
        },
      );
}

class KycIntro extends StatelessWidget {
  const KycIntro({
    super.key,
    required this.step,
    required this.title,
    required this.description,
    required this.icon,
  });
  final String step;
  final String title;
  final String description;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 40, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 20),
          Text(
            step.toUpperCase(),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
          const SizedBox(height: 8),
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Text(description, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 28),
        ],
      );
}

class PrivatePhoto extends StatefulWidget {
  const PrivatePhoto({super.key, required this.bytes, required this.label});
  final List<int>? bytes;
  final String label;
  @override
  State<PrivatePhoto> createState() => _PrivatePhotoState();
}

class _PrivatePhotoState extends State<PrivatePhoto> {
  MemoryImage? _image;
  @override
  void initState() {
    super.initState();
    _setImage();
  }

  void _setImage() {
    _image = widget.bytes == null
        ? null
        : MemoryImage(Uint8List.fromList(widget.bytes!));
  }

  @override
  void didUpdateWidget(PrivatePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.bytes, oldWidget.bytes)) {
      _image?.evict();
      _setImage();
    }
  }

  @override
  void dispose() {
    // Authenticated photos must not remain in Flutter's shared image cache after leaving the flow.
    _image?.evict();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: _image == null
              ? Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.lock_outline, size: 40),
                      Text(widget.label),
                    ],
                  ),
                )
              : Image(
                  image: _image!,
                  fit: BoxFit.contain,
                  semanticLabel: widget.label,
                  errorBuilder: (_, _, _) => Center(
                      child: Text('${widget.label} preview unavailable')),
                ),
        ),
      );
}
