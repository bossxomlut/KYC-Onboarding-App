import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/widgets/form_field_label.dart';

/// Keeps picker changes local until confirmed; the form still stores ISO dates.
class DateOfBirthField extends StatefulWidget {
  const DateOfBirthField({
    super.key,
    required this.value,
    required this.onChanged,
    required this.enabled,
    this.errorText,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final String? errorText;

  @override
  State<DateOfBirthField> createState() => _DateOfBirthFieldState();
}

class _DateOfBirthFieldState extends State<DateOfBirthField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _displayDate(widget.value));
  }

  @override
  void didUpdateWidget(DateOfBirthField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _controller.text = _displayDate(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _displayDate(String value) {
    final date = DateTime.tryParse(value);
    return date == null ? '' : DateFormat('d MMMM yyyy', 'en_US').format(date);
  }

  Future<void> _selectDate() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final today = DateTime.now();
    // A person remains 120 until their 121st birthday, so include that full year.
    final oldestBirthday = _yearsBefore(today, 121);
    final minimum = DateTime(
      oldestBirthday.year,
      oldestBirthday.month,
      oldestBirthday.day + 1,
    );
    final maximum = _yearsBefore(today, 18);
    var selected = DateTime.tryParse(widget.value) ?? _yearsBefore(today, 30);
    if (selected.isBefore(minimum)) selected = minimum;
    if (selected.isAfter(maximum)) selected = maximum;
    final theme = Theme.of(context);
    final result = await showModalBottomSheet<DateTime>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Select your date of birth',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Verification is available for adults aged 18–120.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 216,
                child: CupertinoTheme(
                  data: CupertinoThemeData(
                    brightness: theme.brightness,
                    primaryColor: theme.colorScheme.primary,
                    textTheme: CupertinoTextThemeData(
                      dateTimePickerTextStyle: theme.textTheme.titleLarge,
                    ),
                  ),
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.date,
                    dateOrder: DatePickerDateOrder.dmy,
                    initialDateTime: selected,
                    minimumDate: minimum,
                    maximumDate: maximum,
                    minimumYear: minimum.year,
                    maximumYear: maximum.year,
                    onDateTimeChanged: (date) => selected = date,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const Key('confirm-date-of-birth'),
                      onPressed: () => Navigator.pop(context, selected),
                      child: const Text('Use date'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || result == null || !widget.enabled) return;
    widget.onChanged(result.toIso8601String().substring(0, 10));
  }

  DateTime _yearsBefore(DateTime date, int years) {
    final year = date.year - years;
    final lastDay = DateTime(year, date.month + 1, 0).day;
    return DateTime(year, date.month, date.day > lastDay ? lastDay : date.day);
  }

  @override
  Widget build(BuildContext context) => FormFieldLabel(
    label: 'Date of birth',
    child: Semantics(
      label: 'Date of birth',
      child: TextFormField(
        key: const Key('dateOfBirth'),
        controller: _controller,
        readOnly: true,
        showCursor: false,
        enableInteractiveSelection: false,
        enabled: widget.enabled,
        onTap: _selectDate,
        decoration: InputDecoration(
          hintText: 'Select a date',
          errorText: widget.errorText,
          suffixIcon: const Icon(Icons.calendar_month_outlined),
        ),
      ),
    ),
  );
}
