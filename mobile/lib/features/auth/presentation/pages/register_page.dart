import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../bloc/auth_form_state.dart';
import '../bloc/register_cubit.dart';
import '../widgets/auth_layout.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key, required this.onVerificationRequired});
  final void Function(String) onVerificationRequired;
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      context
          .read<RegisterCubit>()
          .submit(email: _email.text, password: _password.text);
    }
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<RegisterCubit, AuthFormState>(
        listener: (context, state) {
          if (state.status == AuthFormStatus.verificationRequired) {
            widget.onVerificationRequired(state.email!);
          }
        },
        builder: (context, state) => AuthLayout(
          title: 'Create your account',
          subtitle: 'Start with your email. We will send a verification code.',
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
                          decoration:
                              const InputDecoration(labelText: 'Email')),
                      const SizedBox(height: 16),
                      TextFormField(
                          controller: _password,
                          enabled: !state.isLoading,
                          obscureText: true,
                          autofillHints: const [AutofillHints.newPassword],
                          textInputAction: TextInputAction.next,
                          validator: validateNewPassword,
                          decoration: const InputDecoration(
                              labelText: 'Password',
                              helperText:
                                  '12–128 characters, uppercase, lowercase and a number')),
                      const SizedBox(height: 16),
                      TextFormField(
                          controller: _confirm,
                          enabled: !state.isLoading,
                          obscureText: true,
                          onFieldSubmitted: (_) => _submit(),
                          validator: (value) => value != _password.text
                              ? 'Passwords must match.'
                              : null,
                          decoration: const InputDecoration(
                              labelText: 'Confirm password')),
                      const SizedBox(height: 24),
                      AuthSubmitButton(
                          label: 'Create account',
                          isLoading: state.isLoading,
                          onPressed: _submit),
                    ]),
              ),
            ),
            const SizedBox(height: 20),
            TextButton(
                onPressed: state.isLoading ? null : () => context.go('/login'),
                child: const Text('Already have an account? Sign in')),
          ],
        ),
      );
}
