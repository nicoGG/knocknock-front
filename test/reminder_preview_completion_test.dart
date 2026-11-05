import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_preview_dialog.dart';

void main() {
  for (final fail in [false, true]) {
    testWidgets('preview completion success=${!fail}', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime(2026, 11, 5, 12);
      final note = Note(
        id: 'note',
        boardId: 'board',
        title: 'Pagar Spin',
        content: '',
        color: NoteColor.green,
        authorName: 'Nico',
        isCompleted: false,
        positionX: 0,
        positionY: 0,
        createdAt: now,
        updatedAt: now,
        reminderAt: now,
      );
      var completed = false;
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                child: const Text('Abrir'),
                onPressed: () {
                  showNotePreviewDialog(
                    context: context,
                    noteProvider: () => note,
                    assigneesProvider: () => [],
                    onSave: (_, _) async {},
                    onDelete: (_) async {},
                    isReminderCompleted: (_) => completed,
                    onCompleteReminder: (_) async {
                      calls++;
                      if (fail) throw Exception('offline');
                      completed = true;
                    },
                    cardBuilder: (_, _, _, _, _, _) =>
                        const SizedBox.expand(child: Text('Pagar Spin')),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('preview-complete-reminder')));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(
        find.text(fail ? 'Completar recordatorio' : 'Recordatorio completado'),
        findsOneWidget,
      );
      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('preview-complete-reminder')),
      );
      expect(button.onPressed == null, !fail);
      expect(tester.takeException(), isNull);
    });
  }
}
