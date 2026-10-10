import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    this.signatureHeader,
    this.overlapHeader = false,
  });
  final String title;
  final Widget child;
  final List<Widget> actions;
  final bool brandHeader;
  final Widget? bottomBar;
  final Widget? signatureHeader;
  final bool overlapHeader;
  @override
  Widget build(BuildContext context) {
    final signature = signatureHeader != null;
    final scaffold = Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: signature ? AppTheme.primary : null,
        flexibleSpace: signature
            ? const SizedBox.expand(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppTheme.signatureGradient,
                  ),
                ),
              )
            : null,
        foregroundColor: signature ? Colors.white : null,
        titleTextStyle: signature
            ? Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              )
            : null,
        systemOverlayStyle: signature ? SystemUiOverlayStyle.light : null,
        toolbarHeight: signature ? 50 : null,
        centerTitle: signature && !brandHeader,
        title: brandHeader
            ? IdentityBrand(color: signature ? Colors.white : null)
            : Text(title),
        titleSpacing: brandHeader ? 22 : 8,
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
      body: signature
          ? _SignatureBody(
              header: signatureHeader!,
              overlapHeader: overlapHeader,
              bottomInset: bottomBar == null
                  ? MediaQuery.paddingOf(context).bottom
                  : 0,
              child: child,
            )
          : SafeArea(
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
                decoration: BoxDecoration(
                  color: AppTheme.background,
                  border: signature
                      ? null
                      : const Border(top: BorderSide(color: AppTheme.border)),
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
                      padding: EdgeInsets.fromLTRB(
                        signature ? 22 : 24,
                        signature ? 12 : 16,
                        signature ? 22 : 24,
                        signature ? 12 : 16,
                      ),
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
    return scaffold;
  }
}

class _SignatureBody extends StatelessWidget {
  const _SignatureBody({
    required this.header,
    required this.overlapHeader,
    required this.bottomInset,
    required this.child,
  });
  final Widget header;
  final bool overlapHeader;
  final double bottomInset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final content = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: overlapHeader
              ? EdgeInsets.fromLTRB(16, 0, 16, 20 + bottomInset)
              : EdgeInsets.fromLTRB(22, 16, 22, 12 + bottomInset),
          child: child,
        ),
      ),
    );
    final sheet = overlapHeader
        ? Stack(
            children: [
              const Positioned.fill(
                top: 40,
                child: ColoredBox(color: AppTheme.background),
              ),
              content,
            ],
          )
        : DecoratedBox(
            decoration: const BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: content,
          );
    return SingleChildScrollView(
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppTheme.signatureGradient),
        child: Column(children: [header, sheet]),
      ),
    );
  }
}

class KycSignatureIntro extends StatelessWidget {
  const KycSignatureIntro({
    super.key,
    required this.title,
    required this.description,
    this.currentStep,
  });
  final String title;
  final String description;
  final int? currentStep;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned(
        right: 8,
        top: currentStep == null ? -2 : 4,
        child: ExcludeSemantics(
          child: Icon(
            Icons.shield_outlined,
            size: 104,
            color: Colors.white.withValues(alpha: .12),
          ),
        ),
      ),
      Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              22,
              currentStep == null ? 12 : 10,
              22,
              currentStep == null ? 28 : 19,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (currentStep != null) ...[
                  KycStepProgress(currentStep: currentStep!, inverse: true),
                  const SizedBox(height: 20),
                ],
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontSize: currentStep == null ? 30 : 28,
                    height: 1.17,
                    letterSpacing: -.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
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
  const KycStepProgress({
    required this.currentStep,
    this.inverse = false,
    super.key,
  }) : assert(currentStep >= 1 && currentStep <= 4);

  final int currentStep;
  final bool inverse;

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
                  width: inverse ? 20 : 24,
                  height: 1,
                  margin: EdgeInsets.symmetric(horizontal: inverse ? 6 : 8),
                  color: inverse
                      ? Colors.white.withValues(alpha: .55)
                      : number <= currentStep
                      ? AppTheme.primary
                      : AppTheme.border,
                ),
              Container(
                width: inverse ? 26 : 30,
                height: inverse ? 26 : 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: inverse
                      ? (number < currentStep
                            ? Colors.white
                            : number == currentStep
                            ? Colors.transparent
                            : Colors.white.withValues(alpha: .66))
                      : number <= currentStep
                      ? AppTheme.primary
                      : Colors.white,
                  border: Border.all(
                    color: inverse
                        ? (number <= currentStep
                              ? Colors.white
                              : Colors.transparent)
                        : number <= currentStep
                        ? AppTheme.primary
                        : AppTheme.border,
                    width: inverse ? 2 : 1.5,
                  ),
                ),
                child: number < currentStep
                    ? Icon(
                        Icons.check,
                        size: 18,
                        color: inverse ? AppTheme.primary : Colors.white,
                      )
                    : Text(
                        '$number',
                        textScaler: TextScaler.noScaling,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: inverse
                              ? (number == currentStep
                                    ? Colors.white
                                    : AppTheme.primary)
                              : number == currentStep
                              ? Colors.white
                              : AppTheme.muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ],
          ],
        ),
        SizedBox(height: inverse ? 7 : 10),
        Text(
          'STEP $currentStep OF 4',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: inverse ? Colors.white : AppTheme.muted,
            fontSize: inverse ? 11 : 12,
          ),
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
