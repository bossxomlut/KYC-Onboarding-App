import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/navigation/current_route.dart';
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _email.text.trim().toLowerCase();
    final cubit = context.read<PasswordResetCubit>();
    final succeeded = await cubit.request(email);
    if (!succeeded || !mounted || !isCurrentRoute(context)) return;
    context.go(
      Uri(
        path: '/reset-password',
        queryParameters: {'email': email},
      ).toString(),
      extra: cubit.resendAvailableAt,
    );
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<PasswordResetCubit, AuthFormState>(
        builder: (context, state) => AuthLayout(
          title: 'Reset your password',
          subtitle:
              'Enter your email to receive a six digit password reset code.',
          children: [
            AuthFeedback(state: state),
            Form(
              key: _formKey,
              child: TextFormField(
                controller: _email,
                enabled: !state.isLoading,
                validator: validateEmail,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(labelText: 'Email'),
              ),
            ),
            const SizedBox(height: 24),
            AuthSubmitButton(
              label: 'Send reset code',
              loadingLabel: 'Sending code…',
              isLoading: state.isLoading,
              onPressed: _submit,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: state.isLoading ? null : () => context.go('/login'),
              child: const Text('Back to sign in'),
            ),
          ],
        ),
      );
}
