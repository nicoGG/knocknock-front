import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/presentation/widgets/animated_note_checkbox.dart';

void main() {
  Future<void> mount(
    WidgetTester tester, {
    bool completed = false,
    bool reduceMotion = false,
  }) async {
    var value = completed;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => AnimatedNoteCheckbox(
                value: value,
                activeColor: Colors.green,
                checkColor: Colors.white,
                onChanged: (selected) =>
                    update(() => value = selected ?? false),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('celebrates completion and removes the overlay after animation', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byType(Checkbox));
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    expect(
      find.byKey(const ValueKey('note-completion-celebration')),
      findsOneWidget,
    );
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    expect(
      find.byKey(const ValueKey('note-completion-celebration')),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('note-completion-celebration')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid completions reuse one celebration overlay', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byType(Checkbox));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.byType(Checkbox));
    await tester.pump(const Duration(milliseconds: 80));
    expect(
      find.byKey(const ValueKey('note-completion-celebration')),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('note-completion-celebration')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('unchecking does not trigger a celebration', (tester) async {
    await mount(tester, completed: true);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('note-completion-celebration')),
      findsNothing,
    );
  });

  testWidgets('reduced motion completes without celebration', (tester) async {
    await mount(tester, reduceMotion: true);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    expect(
      find.byKey(const ValueKey('note-completion-celebration')),
      findsNothing,
    );
  });
}
