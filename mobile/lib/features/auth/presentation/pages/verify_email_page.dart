import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/user.dart';
import '../bloc/auth_form_state.dart';
import '../bloc/email_verification_cubit.dart';
import '../widgets/auth_layout.dart';

class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage(
      {super.key,
      required this.email,
      required this.onSignedIn,
      this.onChangeEmail});
  final String email;
  final void Function(User) onSignedIn;
  final VoidCallback? onChangeEmail;
  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      context
          .read<EmailVerificationCubit>()
          .submit(email: widget.email, code: _code.text);
    }
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<EmailVerificationCubit, AuthFormState>(
        listenWhen: (previous, current) => previous.status != current.status,
        listener: (context, state) {
          if (state.status == AuthFormStatus.success) {
            widget.onSignedIn(state.user!);
          }
        },
        builder: (context, state) => AuthLayout(
          title: 'Verify your email',
          subtitle:
              'Enter the six digit verification code for ${widget.email}. Request a new code below if it has not arrived.',
          children: [
            AuthFeedback(state: state),
            Form(
                key: _formKey,
                child: TextFormField(
                  controller: _code,
                  enabled: !state.isLoading && !state.isResending,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onFieldSubmitted: (_) => _submit(),
                  validator: (value) =>
                      !RegExp(r'^\d{6}$').hasMatch(value ?? '')
                          ? 'Enter the six digit verification code.'
                          : null,
                  decoration:
                      const InputDecoration(labelText: 'Verification code'),
                )),
            const SizedBox(height: 20),
            AuthSubmitButton(
                label: 'Verify email',
                isLoading: state.isLoading || state.isResending,
                onPressed: _submit),
            const SizedBox(height: 12),
            TextButton(
                onPressed: state.isLoading ||
                        state.isResending ||
                        state.resendSeconds > 0
                    ? null
                    : () => context
                        .read<EmailVerificationCubit>()
                        .resend(widget.email),
                child: Text(state.resendSeconds > 0
                    ? 'Resend code in ${state.resendSeconds}s'
                    : 'Resend verification code')),
            TextButton(
                onPressed: state.isLoading || state.isResending
                    ? null
                    : widget.onChangeEmail ?? () => context.go('/register'),
                child: const Text('Use a different email')),
          ],
        ),
      );
}
