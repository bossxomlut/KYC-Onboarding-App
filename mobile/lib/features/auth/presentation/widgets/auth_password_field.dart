import 'package:flutter/material.dart';

class AuthPasswordField extends StatefulWidget {
  const AuthPasswordField({
    super.key,
    required this.controller,
    required this.decoration,
    this.enabled = true,
    this.autofillHints,
    this.textInputAction,
    this.validator,
    this.onFieldSubmitted,
  });

  final TextEditingController controller;
  final InputDecoration decoration;
  final bool enabled;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  State<AuthPasswordField> createState() => _AuthPasswordFieldState();
}

class _AuthPasswordFieldState extends State<AuthPasswordField> {
  bool _obscureText = true;

  void _toggleVisibility() => setState(() => _obscureText = !_obscureText);

  @override
  Widget build(BuildContext context) {
    final label = widget.decoration.labelText?.toLowerCase() ?? 'password';
    final visibilityLabel = '${_obscureText ? 'Show' : 'Hide'} $label';
    return TextFormField(
      controller: widget.controller,
      enabled: widget.enabled,
      obscureText: _obscureText,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: widget.autofillHints,
      textInputAction: widget.textInputAction,
      validator: widget.validator,
      onFieldSubmitted: widget.onFieldSubmitted,
      decoration: widget.decoration.copyWith(
        suffixIcon: Semantics(
          label: visibilityLabel,
          button: true,
          enabled: widget.enabled,
          toggled: !_obscureText,
          onTap: widget.enabled ? _toggleVisibility : null,
          excludeSemantics: true,
          child: IconButton(
            tooltip: visibilityLabel,
            onPressed: widget.enabled ? _toggleVisibility : null,
            icon: Icon(
              _obscureText
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
          ),
        ),
      ),
    );
  }
}
