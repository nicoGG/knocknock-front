import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_preview_dialog.dart';

void main() {
  testWidgets(
    'hides the attached photo preview while the creation keyboard is open',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      const onePixelPng =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+'
          'A8AAQUBAScY42YAAAAASUVORK5CYII=';
      final now = DateTime.utc(2026, 8, 14);
      final note = Note(
        id: 'new-note-with-photo',
        boardId: 'board-1',
        title: '',
        content: '',
        color: NoteColor.yellow,
        authorName: 'Nico',
        attachments: const [
          NoteAttachment(
            id: 'photo-1',
            name: 'foto.png',
            mimeType: 'image/png',
            sizeBytes: 68,
            dataBase64: onePixelPng,
          ),
        ],
        isCompleted: false,
        positionX: 0,
        positionY: 0,
        createdAt: now,
        updatedAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  key: const ValueKey('open-create-dialog'),
                  onPressed: () => showCreateNoteDialog(
                    context: context,
                    defaultAuthorName: 'Nico',
                    showAuthorField: false,
                    assignees: const [],
                    initialNote: note,
                  ),
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('open-create-dialog')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('quick-photo-photo-1')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('add-description-button')));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();

      expect(find.byKey(const ValueKey('quick-photo-photo-1')), findsNothing);
      expect(find.byKey(const ValueKey('note-content-editor')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('quick-editor-attachment-action')),
        findsOneWidget,
      );

      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pump();

      expect(find.byKey(const ValueKey('quick-photo-photo-1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
