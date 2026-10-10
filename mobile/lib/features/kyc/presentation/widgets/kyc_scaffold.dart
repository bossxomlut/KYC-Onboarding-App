import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/identity_brand.dart';
import '../bloc/kyc_cubit.dart';

class KycScaffold extends StatelessWidget {
  const KycScaffold({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.brandHeader = false,
    this.bottomBar,
  });
  final String title;
  final Widget child;
  final List<Widget> actions;
  final bool brandHeader;
  final Widget? bottomBar;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: brandHeader ? const IdentityBrand() : Text(title),
      titleSpacing: brandHeader ? 24 : 8,
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
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: child,
          ),
        ),
      ),
    ),
    bottomNavigationBar: bottomBar == null
        ? null
        : Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: AppTheme.background,
                border: Border(top: BorderSide(color: AppTheme.border)),
              ),
              child: SafeArea(
                top: false,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight:
                        (MediaQuery.sizeOf(context).height -
                            MediaQuery.viewInsetsOf(context).bottom) *
                        .45,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 512),
                        child: SizedBox(
                          width: double.infinity,
                          child: bottomBar!,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
  );
}

class KycError extends StatelessWidget {
  const KycError({super.key, this.onRetry, this.retryKey});
  final VoidCallback? onRetry;
  final Key? retryKey;
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
                key: retryKey,
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
      if (RegExp(r'^Step ([1-4]) of 4$').hasMatch(step)) ...[
        KycStepProgress(
          currentStep: int.parse(
            RegExp(r'^Step ([1-4]) of 4$').firstMatch(step)!.group(1)!,
          ),
        ),
        const SizedBox(height: 20),
      ] else ...[
        Row(
          children: [
            Icon(icon, size: 20, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text(
              step.toUpperCase(),
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
      Text(title, style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 8),
      Text(
        description,
        style: Theme.of(
          context,
        ).textTheme.bodyLarge?.copyWith(color: AppTheme.muted),
      ),
      const SizedBox(height: 20),
    ],
  );
}

class KycStepProgress extends StatelessWidget {
  const KycStepProgress({required this.currentStep, super.key})
    : assert(currentStep >= 1 && currentStep <= 4);

  final int currentStep;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Step $currentStep of 4',
    excludeSemantics: true,
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var number = 1; number <= 4; number++) ...[
              if (number > 1)
                Container(
                  width: 24,
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  color: number <= currentStep
                      ? AppTheme.primary
                      : AppTheme.border,
                ),
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: number <= currentStep
                      ? AppTheme.primary
                      : Colors.white,
                  border: Border.all(
                    color: number <= currentStep
                        ? AppTheme.primary
                        : AppTheme.border,
                    width: 1.5,
                  ),
                ),
                child: number < currentStep
                    ? const Icon(Icons.check, size: 18, color: Colors.white)
                    : Text(
                        '$number',
                        textScaler: TextScaler.noScaling,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: number == currentStep
                              ? Colors.white
                              : AppTheme.muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'STEP $currentStep OF 4',
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    ),
  );
}

class PrivatePhoto extends StatefulWidget {
  const PrivatePhoto({
    super.key,
    required this.bytes,
    required this.label,
    this.placeholder,
    this.aspectRatio = 4 / 3,
  });
  final List<int>? bytes;
  final String label;
  final Widget? placeholder;
  final double aspectRatio;
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
      aspectRatio: widget.aspectRatio,
      child: _image == null
          ? widget.placeholder ??
                Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Semantics(
                    label: widget.label,
                    excludeSemantics: true,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.lock_outline, size: 40),
                          const SizedBox(height: 8),
                          Flexible(
                            child: Text(
                              widget.label,
                              textAlign: TextAlign.center,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
          : Image(
              image: _image!,
              fit: BoxFit.contain,
              semanticLabel: widget.label,
              errorBuilder: (_, _, _) =>
                  Center(child: Text('${widget.label} preview unavailable')),
            ),
    ),
  );
}
