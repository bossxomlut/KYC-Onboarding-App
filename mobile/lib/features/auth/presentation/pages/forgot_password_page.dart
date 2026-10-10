import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../bloc/auth_form_state.dart';
import '../bloc/password_reset_cubit.dart';
import '../widgets/auth_layout.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});
  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      context.read<PasswordResetCubit>().request(_email.text);
    }
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<PasswordResetCubit, AuthFormState>(
        builder: (context, state) => AuthLayout(
            title: 'Reset your password',
            subtitle: 'We will email instructions to help you regain access.',
            children: [
              AuthFeedback(state: state),
              if (state.status != AuthFormStatus.success) ...[
                Form(
                    key: _formKey,
                    child: TextFormField(
                        controller: _email,
                        enabled: !state.isLoading,
                        validator: validateEmail,
                        keyboardType: TextInputType.emailAddress,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(labelText: 'Email'))),
                const SizedBox(height: 24),
                AuthSubmitButton(
                    label: 'Send reset instructions',
                    isLoading: state.isLoading,
                    onPressed: _submit),
              ],
              const SizedBox(height: 12),
              TextButton(
                  onPressed: state.isLoading
                      ? null
                      : () => context.go('/reset-password'),
                  child: const Text('I have a reset token')),
              TextButton(
                  onPressed:
                      state.isLoading ? null : () => context.go('/login'),
                  child: const Text('Back to sign in')),
            ]),
      );
}
