import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_link.dart';
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

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(savedDraft?.checklist.map((item) => item.text), ['Leche', 'Avena']);
    expect(
      find.byKey(const ValueKey('quick-edit-checklist-editor')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'add another subtask appends and focuses a row with a finish check',
    (tester) async {
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      NoteDraft? savedDraft;
      final note = Note(
        id: 'travel-note',
        boardId: 'home',
        title: 'Pasajes',
        content: 'Comprar pasajes',
        color: NoteColor.orange,
        authorName: 'Nico',
        isCompleted: false,
        positionX: 0,
        positionY: 0,
        checklist: const [
          NoteChecklistItem(id: 'easter-island', text: 'Isla de Pascua'),
          NoteChecklistItem(id: 'rio', text: 'Río de Janeiro'),
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

      await tester.tap(find.byKey(const ValueKey('add-inline-subtask-button')));
      await tester.pumpAndSettle();

      final editor = find.byKey(const ValueKey('quick-edit-checklist-editor'));
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
      expect(
        find.byKey(const ValueKey('finish-inline-checklist-button')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('finish-inline-checklist-button')),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );

      await tester.enterText(fields.last, 'Reservar hotel');
      await tester.tap(
        find.byKey(const ValueKey('finish-inline-checklist-button')),
      );
      await tester.pumpAndSettle();

      expect(savedDraft?.checklist.map((item) => item.text), [
        'Isla de Pascua',
        'Río de Janeiro',
        'Reservar hotel',
      ]);
      expect(editor, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a subtask can use a renamed link', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final editTarget = ValueNotifier(PostItInlineEditTarget.none);
    addTearDown(editTarget.dispose);
    NoteDraft? savedDraft;
    final note = Note(
      id: 'linked-note',
      boardId: 'home',
      title: 'Compras',
      content: '',
      color: NoteColor.orange,
      authorName: 'Nico',
      isCompleted: false,
      positionX: 0,
      positionY: 0,
      checklist: const [NoteChecklistItem(id: 'eggs', text: 'Huevos')],
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
    await tester.tap(
      find.byKey(const ValueKey('edit-inline-checklist-link-eggs')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Agregar vínculo'), findsOneWidget);
    final labelField = find.byKey(const ValueKey('note-link-label-field'));
    final urlField = find.byKey(const ValueKey('note-link-url-field'));
    expect(tester.widget<TextFormField>(labelField).controller?.text, 'Huevos');
    await tester.enterText(labelField, 'Huevos orgánicos');
    await tester.enterText(urlField, 'super.cl/huevos');
    await tester.tap(find.byKey(const ValueKey('save-note-link-button')));
    await tester.pumpAndSettle();

    expect(find.text('Huevos orgánicos'), findsOneWidget);
    final taskField = find.byKey(const ValueKey('checklist-text-eggs'));
    await tester.enterText(taskField, '');
    await tester.pump();
    await tester.enterText(taskField, 'Huevos de campo');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    final savedLink = noteChecklistLinkFromText(
      savedDraft!.checklist.single.text,
    );
    expect(savedLink?.label, 'Huevos de campo');
    expect(savedLink?.url, 'https://super.cl/huevos');
    expect(find.text('https://super.cl/huevos'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('description saves automatically when it loses focus', (
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

    final editor = tester.widget<QuillEditor>(editorFinder);
    const editedContent = 'Lavar la ropita con cuidado';
    editor.controller.replaceText(
      0,
      editor.controller.document.length - 1,
      editedContent,
      const TextSelection.collapsed(offset: editedContent.length),
    );
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    expect(savedDraft?.content, editedContent);
    expect(
      find.byKey(const ValueKey('save-inline-description-button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('cancel-inline-description-button')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
