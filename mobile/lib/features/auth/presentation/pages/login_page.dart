import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/user.dart';
import '../bloc/auth_form_state.dart';
import '../bloc/login_cubit.dart';
import '../widgets/auth_layout.dart';
import '../widgets/auth_password_field.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.onSignedIn,
    required this.onVerificationRequired,
  });
  final void Function(User) onSignedIn;
  final void Function(String) onVerificationRequired;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      context.read<LoginCubit>().submit(
        email: _email.text,
        password: _password.text,
      );
    }
  }

  @override
  Widget build(BuildContext context) => BlocConsumer<LoginCubit, AuthFormState>(
    listener: (context, state) {
      if (state.status == AuthFormStatus.success) {
        widget.onSignedIn(state.user!);
      }
      if (state.status == AuthFormStatus.verificationRequired) {
        widget.onVerificationRequired(state.email!);
      }
    },
    builder: (context, state) => AuthLayout(
      title: 'Welcome back',
      subtitle: 'Sign in to continue your identity verification.',
      children: [
        AuthFeedback(state: state),
        Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _email,
                  enabled: !state.isLoading,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  validator: validateEmail,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                ),
                const SizedBox(height: 16),
                AuthPasswordField(
                  controller: _password,
                  enabled: !state.isLoading,
                  autofillHints: const [AutofillHints.password],
                  onFieldSubmitted: (_) => _submit(),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Enter your password.'
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: state.isLoading
                        ? null
                        : () => context.go('/forgot-password'),
                    child: const Text('Forgot password?'),
                  ),
                ),
                const SizedBox(height: 16),
                AuthSubmitButton(
                  label: 'Sign in',
                  loadingLabel: 'Signing in…',
                  isLoading: state.isLoading,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        TextButton(
          onPressed: state.isLoading ? null : () => context.go('/register'),
          child: const Text('New here? Create an account'),
        ),
      ],
    ),
  );
}
