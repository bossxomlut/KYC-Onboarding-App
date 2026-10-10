import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../bloc/auth_form_state.dart';
import '../bloc/password_reset_cubit.dart';
import '../widgets/auth_layout.dart';
import '../widgets/auth_password_field.dart';

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key, this.token = ''});
  final String token;
  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  late final _token = TextEditingController(text: widget.token);
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  @override
  void dispose() {
    _token.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      context.read<PasswordResetCubit>().reset(
        token: _token.text,
        newPassword: _password.text,
      );
    }
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
