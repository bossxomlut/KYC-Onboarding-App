import 'package:flutter/material.dart';

import '../bloc/auth_form_state.dart';

class AuthLayout extends StatelessWidget {
  const AuthLayout(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.children});
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
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(20)),
                      child: Icon(Icons.verified_user_outlined,
                          size: 34, color: theme.colorScheme.primary),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(title,
                      style: theme.textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(subtitle,
                      style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 32),
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
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: state.error != null
                  ? scheme.errorContainer
                  : scheme.primaryContainer,
              borderRadius: BorderRadius.circular(12)),
          child: Text(message,
              style: TextStyle(
                  color: state.error != null
                      ? scheme.onErrorContainer
                      : scheme.onPrimaryContainer)),
        ),
      ),
    );
  }
}

class AuthSubmitButton extends StatelessWidget {
  const AuthSubmitButton(
      {super.key,
      required this.label,
      required this.isLoading,
      required this.onPressed});
  final String label;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: isLoading ? null : onPressed,
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Text(label),
      );
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
