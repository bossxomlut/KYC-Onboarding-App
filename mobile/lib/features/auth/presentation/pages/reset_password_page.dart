import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../bloc/auth_form_state.dart';
import '../bloc/password_reset_cubit.dart';
import '../widgets/auth_layout.dart';
import '../widgets/auth_password_field.dart';

typedef PasswordResetCompletion = Future<void> Function();

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({
    super.key,
    this.token = '',
    this.onPasswordReset,
    this.onPasswordResetStarted,
  });
  final String token;
  final PasswordResetCompletion? onPasswordReset;
  final PasswordResetCompletion Function()? onPasswordResetStarted;
  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  var _formKey = GlobalKey<FormState>();
  late final _token = TextEditingController(text: widget.token);
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  @override
  void didUpdateWidget(covariant ResetPasswordPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.token == widget.token) return;
    _token.text = widget.token;
    _password.clear();
    _confirm.clear();
    _formKey = GlobalKey<FormState>();
    context.read<PasswordResetCubit>().resetForm();
  }

  @override
  void dispose() {
    _token.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final onPasswordReset =
        widget.onPasswordResetStarted?.call() ?? widget.onPasswordReset;
    final succeeded = await context.read<PasswordResetCubit>().reset(
      token: _token.text,
      newPassword: _password.text,
    );
    // Revocation belongs to the submitted operation even if its form changed.
    if (succeeded) await onPasswordReset?.call();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<PasswordResetCubit, AuthFormState>(
    builder: (context, state) => AuthLayout(
      title: 'Choose a new password',
      subtitle: 'Paste the token from your reset email and set a new password.',
      children: [
        AuthFeedback(state: state),
        if (state.status != AuthFormStatus.success) ...[
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _token,
                  enabled: !state.isLoading,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.next,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter the reset token from your email.'
                      : null,
                  decoration: const InputDecoration(labelText: 'Reset token'),
                ),
                const SizedBox(height: 16),
                AuthPasswordField(
                  controller: _password,
                  enabled: !state.isLoading,
                  textInputAction: TextInputAction.next,
                  validator: validateNewPassword,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: const InputDecoration(
                    labelText: 'New password',
                    helperText:
                        '12–128 characters, uppercase, lowercase and a number',
                  ),
                ),
                const SizedBox(height: 16),
                AuthPasswordField(
                  controller: _confirm,
                  enabled: !state.isLoading,
                  onFieldSubmitted: (_) => _submit(),
                  validator: (value) =>
                      value != _password.text ? 'Passwords must match.' : null,
                  decoration: const InputDecoration(
                    labelText: 'Confirm new password',
                  ),
                ),
                const SizedBox(height: 24),
                AuthSubmitButton(
                  label: 'Change password',
                  isLoading: state.isLoading,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        TextButton(
          onPressed: state.isLoading ? null : () => context.go('/login'),
          child: const Text('Back to sign in'),
        ),
      ],
    ),
  );
}
