import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../bloc/auth_form_state.dart';
import '../bloc/password_reset_cubit.dart';
import '../widgets/auth_layout.dart';
import '../widgets/auth_password_field.dart';
import '../widgets/otp_code_field.dart';

typedef PasswordResetCompletion = Future<void> Function();

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({
    super.key,
    required this.email,
    this.resendAvailableAt,
    this.onPasswordReset,
    this.onPasswordResetStarted,
  });
  final String email;
  final DateTime? resendAvailableAt;
  final PasswordResetCompletion? onPasswordReset;
  final PasswordResetCompletion Function()? onPasswordResetStarted;
  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  var _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  String get _email => widget.email.trim().toLowerCase();

  @override
  void didUpdateWidget(covariant ResetPasswordPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final cubit = context.read<PasswordResetCubit>();
    if (oldWidget.email.trim().toLowerCase() != _email) {
      _code.clear();
      _password.clear();
      _confirm.clear();
      _formKey = GlobalKey<FormState>();
      cubit.resetForm(email: _email);
    }
    if (oldWidget.resendAvailableAt != widget.resendAvailableAt &&
        widget.resendAvailableAt != null) {
      cubit.startCooldown(availableAt: widget.resendAvailableAt);
    }
  }

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final onPasswordReset =
        widget.onPasswordResetStarted?.call() ?? widget.onPasswordReset;
    final succeeded = await context.read<PasswordResetCubit>().reset(
      email: _email,
      code: _code.text,
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
      subtitle: 'Enter the six digit code for $_email and set a new password.',
      children: [
        AuthFeedback(state: state),
        if (state.status != AuthFormStatus.success) ...[
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OtpCodeField(
                  controller: _code,
                  enabled: !state.isLoading && !state.isResending,
                  onSubmitted: _submit,
                ),
                const SizedBox(height: 16),
                AuthPasswordField(
                  controller: _password,
                  enabled: !state.isLoading && !state.isResending,
                  textInputAction: TextInputAction.next,
                  validator: validateNewPassword,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    labelText: 'New password',
                    helper: Text(
                      '12–128 characters, uppercase, lowercase and a number',
                      softWrap: true,
                      overflow: TextOverflow.visible,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    errorMaxLines: 3,
                  ),
                ),
                const SizedBox(height: 16),
                AuthPasswordField(
                  controller: _confirm,
                  enabled: !state.isLoading && !state.isResending,
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
                  loadingLabel: state.isResending
                      ? 'Sending code…'
                      : 'Changing password…',
                  isLoading: state.isLoading || state.isResending,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed:
                state.isLoading || state.isResending || state.resendSeconds > 0
                ? null
                : () => context.read<PasswordResetCubit>().resend(_email),
            child: Text(
              state.isResending
                  ? 'Sending code…'
                  : state.resendSeconds > 0
                  ? 'Resend code in ${state.resendSeconds}s'
                  : 'Resend reset code',
            ),
          ),
          TextButton(
            onPressed: state.isLoading || state.isResending
                ? null
                : () => context.go('/reset-password'),
            child: const Text('Use a different email'),
          ),
        ],
        const SizedBox(height: 20),
        TextButton(
          onPressed: state.isLoading || state.isResending
              ? null
              : () => context.go('/login'),
          child: const Text('Back to sign in'),
        ),
      ],
    ),
  );
}
