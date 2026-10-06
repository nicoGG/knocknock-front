import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_checklist.dart';

void main() {
  testWidgets('subtasks move down on completion and up when restored', (
    tester,
  ) async {
    var items = const [
      NoteChecklistItem(id: 'a', text: 'Primera'),
      NoteChecklistItem(id: 'b', text: 'Segunda'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: StatefulBuilder(
              builder: (context, update) => NoteChecklistPreview(
                items: items,
                foregroundColor: Colors.black,
                onToggle: (item) => update(() {
                  items = items
                      .map(
                        (current) => current.id == item.id
                            ? current.copyWith(
                                isCompleted: !current.isCompleted,
                              )
                            : current,
                      )
                      .toList();
                }),
              ),
            ),
          ),
        ),
      ),
    );
    final first = find.byKey(const ValueKey('preview-check-a'));
    final originalTop = tester.getTopLeft(first).dy;
    await tester.tap(first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(items.first.isCompleted, isFalse);
    expect(
      tester
          .widget<Transform>(find.byKey(const ValueKey('subtask-slide-a')))
          .transform
          .entry(1, 3),
      greaterThan(0),
    );
    await tester.pumpAndSettle();
    expect(items.first.isCompleted, isTrue);
    expect(tester.getTopLeft(first).dy, greaterThan(originalTop));
    await tester.tap(first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(items.first.isCompleted, isTrue);
    expect(
      tester
          .widget<Transform>(find.byKey(const ValueKey('subtask-slide-a')))
          .transform
          .entry(1, 3),
      lessThan(0),
    );
    await tester.pumpAndSettle();
    expect(items.first.isCompleted, isFalse);
    expect(tester.getTopLeft(first).dy, originalTop);
    expect(tester.takeException(), isNull);
  });
}
