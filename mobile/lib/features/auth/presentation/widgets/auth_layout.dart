import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/identity_brand.dart';
import '../bloc/auth_form_state.dart';

class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
  });
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const IdentityBrand(),
                  const SizedBox(height: 36),
                  Text(
                    title,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: AppTheme.muted,
                    ),
                  ),
                  const SizedBox(height: 28),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthFeedback extends StatelessWidget {
  const AuthFeedback({super.key, required this.state});
  final AuthFormState state;

  @override
  Widget build(BuildContext context) {
    final message = state.error?.message ?? state.message;
    if (message == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: state.error != null
                ? scheme.errorContainer
                : scheme.primaryContainer,
            borderRadius: BorderRadius.circular(AppTheme.controlRadius),
          ),
          child: Text(
            message,
            style: TextStyle(
              color: state.error != null
                  ? scheme.onErrorContainer
                  : scheme.onPrimaryContainer,
            ),
          ),
        ),
      ),
    );
  }
}

class AuthSubmitButton extends StatelessWidget {
  const AuthSubmitButton({
    super.key,
    required this.label,
    required this.isLoading,
    required this.onPressed,
    this.loadingLabel,
  });
  final String label;
  final String? loadingLabel;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final progress = SizedBox.square(
      dimension: 22,
      child: isLoading
          ? CircularProgressIndicator(strokeWidth: 2, color: colors.onPrimary)
          : null,
    );
    return FilledButton(
      onPressed: isLoading ? null : onPressed,
      style: isLoading
          ? FilledButton.styleFrom(
              disabledBackgroundColor: colors.primary,
              disabledForegroundColor: colors.onPrimary,
            )
          : null,
      child: Semantics(
        liveRegion: isLoading,
        // Measure both states so changing content never resizes the button.
        child: IndexedStack(
          index: isLoading ? 1 : 0,
          alignment: Alignment.center,
          children: [
            Text(label),
            if (loadingLabel == null)
              progress
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  progress,
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(loadingLabel!, textAlign: TextAlign.center),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

String? validateEmail(String? value) {
  final email = value?.trim() ?? '';
  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
    return 'Enter a valid email address.';
  }
  return null;
}

String? validateNewPassword(String? value) {
  if (value == null || value.length < 12 || value.length > 128) {
    return 'Use 12–128 characters.';
  }
  if (!RegExp(r'[a-z]').hasMatch(value) ||
      !RegExp(r'[A-Z]').hasMatch(value) ||
      !RegExp(r'[0-9]').hasMatch(value)) {
    return 'Include uppercase, lowercase and a number.';
  }
  return null;
}
