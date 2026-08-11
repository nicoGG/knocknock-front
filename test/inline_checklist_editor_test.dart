import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/presentation/widgets/post_it_card.dart';

void main() {
  testWidgets('inline subtasks use a simple flat reorderable list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final editTarget = ValueNotifier(PostItInlineEditTarget.none);
    addTearDown(editTarget.dispose);
    NoteDraft? savedDraft;
    final note = Note(
      id: 'simple-note',
      boardId: 'home',
      title: 'Compras',
      content: 'Para el desayuno',
      color: NoteColor.orange,
      authorName: 'Nico',
      isCompleted: false,
      positionX: 0,
      positionY: 0,
      checklist: const [
        NoteChecklistItem(id: 'eggs', text: 'Huevos'),
        NoteChecklistItem(id: 'milk', text: 'Leche'),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 390,
              height: 720,
              child: PostItCard(
                note: note,
                layout: PostItCardLayout.large,
                inlineEditTarget: editTarget,
                onInlineSave: (draft) async {
                  savedDraft = draft;
                  return true;
                },
                onToggle: () {},
                onPin: () {},
                onOpen: () {},
                onChecklistToggle: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('edit-inline-checklist-button')),
    );
    await tester.pumpAndSettle();

    final editor = find.byKey(const ValueKey('quick-edit-checklist-editor'));
    expect(editor, findsOneWidget);
    expect(
      find.descendant(of: editor, matching: find.byType(PopupMenuButton)),
      findsNothing,
    );
    expect(
      find.descendant(
        of: editor,
        matching: find.byIcon(Icons.drag_indicator_rounded),
      ),
      findsNWidgets(2),
    );
    expect(
      find.byKey(const ValueKey('delete-inline-checklist-eggs')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('add-checklist-item')),
        matching: find.text('Elemento de la lista'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('add-checklist-item')));
    await tester.pump();
    final fields = find.descendant(
      of: editor,
      matching: find.byType(TextFormField),
    );
    expect(fields, findsNWidgets(3));
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: fields.last,
              matching: find.byType(EditableText),
            ),
          )
          .focusNode
          .hasFocus,
      isTrue,
    );
    await tester.enterText(fields.last, 'avena');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('add-checklist-item')));
    await tester.pump();
    final fieldsWithWhitespace = find.descendant(
      of: editor,
      matching: find.byType(TextFormField),
    );
    expect(fieldsWithWhitespace, findsNWidgets(4));
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: fieldsWithWhitespace.last,
              matching: find.byType(EditableText),
            ),
          )
          .focusNode
          .hasFocus,
      isTrue,
    );
    await tester.enterText(fieldsWithWhitespace.last, '   ');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('add-checklist-item')));
    await tester.pump();
    final fieldsWithEmpty = find.descendant(
      of: editor,
      matching: find.byType(TextFormField),
    );
    expect(fieldsWithEmpty, findsNWidgets(5));
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: fieldsWithEmpty.last,
              matching: find.byType(EditableText),
            ),
          )
          .focusNode
          .hasFocus,
      isTrue,
    );
    await tester.tap(
      find.byKey(const ValueKey('delete-inline-checklist-eggs')),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('save-inline-checklist-button')),
    );
    await tester.pumpAndSettle();

    expect(savedDraft?.checklist.map((item) => item.text), ['Leche', 'Avena']);
    expect(
      find.byKey(const ValueKey('quick-edit-checklist-editor')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('description X clears locally and persists only after save', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final editTarget = ValueNotifier(PostItInlineEditTarget.none);
    addTearDown(editTarget.dispose);
    NoteDraft? savedDraft;
    final note = Note(
      id: 'description-note',
      boardId: 'home',
      title: 'Comprar peróxido',
      content: 'Para sacar manchas de la ropita',
      color: NoteColor.coral,
      authorName: 'Nico',
      isCompleted: false,
      positionX: 0,
      positionY: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 390,
              height: 720,
              child: PostItCard(
                note: note,
                layout: PostItCardLayout.large,
                inlineEditTarget: editTarget,
                onInlineSave: (draft) async {
                  savedDraft = draft;
                  return true;
                },
                onToggle: () {},
                onPin: () {},
                onOpen: () {},
                onChecklistToggle: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey('inline-description-hit-target-description-note'),
      ),
    );
    await tester.pumpAndSettle();
    final editorFinder = find.byKey(
      const ValueKey('quick-edit-content-editor'),
    );
    expect(
      tester
          .widget<QuillEditor>(editorFinder)
          .controller
          .document
          .toPlainText()
          .trim(),
      note.content,
    );

    final delete = find.byKey(
      const ValueKey('delete-inline-description-button'),
    );
    await tester.ensureVisible(delete);
    await tester.tap(delete);
    await tester.pumpAndSettle();

    expect(savedDraft, isNull);
    expect(
      tester
          .widget<QuillEditor>(editorFinder)
          .controller
          .document
          .toPlainText()
          .trim(),
      isEmpty,
    );

    final save = find.byKey(const ValueKey('save-inline-description-button'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(savedDraft?.content, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
