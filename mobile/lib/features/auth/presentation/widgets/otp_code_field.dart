import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Six visible cells backed by native text editing so paste, autofill and
/// backspace work as one verification code, including leading zeroes.
class OtpCodeField extends StatefulWidget {
  const OtpCodeField({
    super.key,
    required this.controller,
    required this.onSubmitted,
    this.enabled = true,
  });

  final TextEditingController controller;
  final VoidCallback onSubmitted;
  final bool enabled;

  @override
  State<OtpCodeField> createState() => _OtpCodeFieldState();
}

class _OtpCodeFieldState extends State<OtpCodeField> {
  static const _length = 6;
  static const _gap = 8.0;
  final _fieldKey = GlobalKey<FormFieldState<String>>();
  final _focus = FocusNode();
  int _tappedCell = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_updateCode);
    _focus.addListener(_updateFocus);
  }

  @override
  void didUpdateWidget(covariant OtpCodeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_updateCode);
      widget.controller.addListener(_updateCode);
      _updateCode();
    }
  }

  void _updateCode() {
    final field = _fieldKey.currentState;
    field?.didChange(widget.controller.text);
    if (field?.hasError ?? false) field!.validate();
    setState(() {});
  }

  void _updateFocus() => setState(() {});

  void _selectCell() {
    final code = widget.controller.text;
    widget.controller.selection = _tappedCell < code.length
        ? TextSelection(baseOffset: _tappedCell, extentOffset: _tappedCell + 1)
        : TextSelection.collapsed(offset: code.length);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateCode);
    _focus.removeListener(_updateFocus);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormField<String>(
    key: _fieldKey,
    initialValue: widget.controller.text,
    enabled: widget.enabled,
    validator: (value) => RegExp(r'^\d{6}$').hasMatch(value ?? '')
        ? null
        : 'Enter the six digit verification code.',
    builder: (field) {
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      final code = widget.controller.text;
      final selection = widget.controller.selection;
      final activeCell = math.min(
        selection.isValid ? selection.start : code.length,
        _length - 1,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Verification code'),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) => SizedBox(
              height: 64,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ExcludeSemantics(
                    child: Row(
                      children: [
                        for (var index = 0; index < _length; index++) ...[
                          if (index > 0) const SizedBox(width: _gap),
                          Expanded(
                            child: AnimatedContainer(
                              key: ValueKey('otp-digit-$index'),
                              duration: const Duration(milliseconds: 120),
                              height: 64,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: widget.enabled
                                    ? colors.surface
                                    : colors.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: field.hasError
                                      ? colors.error
                                      : _focus.hasFocus &&
                                            widget.enabled &&
                                            index == activeCell
                                      ? colors.primary
                                      : colors.outlineVariant,
                                  width:
                                      field.hasError ||
                                          (_focus.hasFocus &&
                                              widget.enabled &&
                                              index == activeCell)
                                      ? 2
                                      : 1,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    index < code.length ? code[index] : '',
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Listener(
                    onPointerDown: (event) {
                      final cellWidth = (constraints.maxWidth + _gap) / _length;
                      _tappedCell = (event.localPosition.dx / cellWidth)
                          .floor()
                          .clamp(0, _length - 1);
                    },
                    child: Semantics(
                      label: 'Verification code, six digits',
                      child: TextSelectionTheme(
                        data: const TextSelectionThemeData(
                          selectionColor: Colors.transparent,
                        ),
                        child: TextField(
                          key: const ValueKey('otp-input'),
                          controller: widget.controller,
                          focusNode: _focus,
                          enabled: widget.enabled,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.oneTimeCode],
                          autocorrect: false,
                          enableSuggestions: false,
                          showCursor: false,
                          style: const TextStyle(color: Colors.transparent),
                          inputFormatters: [_OtpInputFormatter(_length)],
                          onTapAlwaysCalled: true,
                          onTap: _selectCell,
                          onSubmitted: (_) => widget.onSubmitted(),
                          decoration: const InputDecoration(
                            filled: false,
                            contentPadding: EdgeInsets.zero,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (field.hasError)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  field.errorText!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.error,
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _OtpInputFormatter extends TextInputFormatter {
  _OtpInputFormatter(this.length);

  final int length;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final selection = oldValue.selection;
    if (selection.isValid && selection.end <= oldValue.text.length) {
      final prefix = oldValue.text.substring(0, selection.start);
      final suffix = oldValue.text.substring(selection.end);
      if (newValue.text.length >= prefix.length + suffix.length &&
          newValue.text.startsWith(prefix) &&
          newValue.text.endsWith(suffix)) {
        final insertedDigits = newValue.text
            .substring(prefix.length, newValue.text.length - suffix.length)
            .replaceAll(RegExp(r'[^0-9]'), '');
        // Pasting a complete code replaces the old code, even mid-edit.
        if (insertedDigits.length >= length) {
          return TextEditingValue(
            text: insertedDigits.substring(0, length),
            selection: TextSelection.collapsed(offset: length),
          );
        }
      }
    }
    final digits = FilteringTextInputFormatter.digitsOnly.formatEditUpdate(
      oldValue,
      newValue,
    );
    return LengthLimitingTextInputFormatter(
      length,
    ).formatEditUpdate(oldValue, digits);
  }
}
