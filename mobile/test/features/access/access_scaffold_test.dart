import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/features/access/presentation/widgets/access_scaffold.dart';

void main() {
  testWidgets('loading preserves input identity, focus and position', (
    tester,
  ) async {
    final busy = ValueNotifier(false);
    final controller = TextEditingController();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      busy.dispose();
      controller.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: busy,
          builder: (_, value, _) => AccessScaffold(
            title: 'Account access',
            busy: value,
            children: [
              const Text('Enter a request'),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  key: const Key('draft'),
                  controller: controller,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final field = find.byKey(const Key('draft'));
    await tester.enterText(field, 'Keep this draft');
    await tester.pump();
    final input = tester.state<EditableTextState>(find.byType(EditableText));
    final position = tester.getTopLeft(field);
    final selection = controller.selection;

    for (final loading in [true, false]) {
      busy.value = loading;
      await tester.pump();

      expect(tester.state<EditableTextState>(find.byType(EditableText)), input);
      expect(input.widget.focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(controller.text, 'Keep this draft');
      expect(controller.selection, selection);
      expect(tester.getTopLeft(field), position);
    }
  });
}
