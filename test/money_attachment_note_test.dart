import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/core/input_formatters/money_text_input_formatter.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_editor_sheet.dart';
import 'package:nocknock/features/notes/presentation/widgets/post_it_card.dart';

void main() {
  test('formats Chilean peso amounts while typing', () {
    final formatter = MoneyTextInputFormatter();

    final value = formatter.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(text: '5000'),
    );

    expect(value.text, r'$5.000');
    expect(value.selection.baseOffset, value.text.length);
  });

  test('round-trips money notes with a custom assignee and attachment', () {
    final now = DateTime.utc(2026, 8, 12);
    final note = Note(
      id: 'note-money',
      boardId: 'board-1',
      title: r'$5.000',
      content: 'Préstamo pendiente',
      color: NoteColor.green,
      authorName: 'Nico',
      customAssigneeName: 'Camila',
      attachment: const NoteAttachment(
        id: 'attachment-1',
        name: 'comprobante.pdf',
        mimeType: 'application/pdf',
        sizeBytes: 128,
      ),
      category: NoteCategory.money,
      isCompleted: false,
      positionX: 0,
      positionY: 0,
      createdAt: now,
      updatedAt: now,
    );

    final restored = Note.fromJson(note.toJson());

    expect(restored, note);
    expect(restored.customAssigneeName, 'Camila');
    expect(restored.attachment?.isPdf, isTrue);
    expect(restored.category, NoteCategory.money);
  });

  testWidgets('mosaic shows only a clip while large preview shows the file', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 12);
    final note = Note(
      id: 'note-attachment',
      boardId: 'board-1',
      title: 'Comprobante',
      content: '',
      color: NoteColor.yellow,
      authorName: 'Nico',
      attachment: const NoteAttachment(
        id: 'attachment-1',
        name: 'comprobante.pdf',
        mimeType: 'application/pdf',
        sizeBytes: 128,
      ),
      isCompleted: false,
      positionX: 0,
      positionY: 0,
      createdAt: now,
      updatedAt: now,
    );

    Future<void> pumpCard(PostItCardLayout layout) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: layout == PostItCardLayout.grid ? 240 : 520,
              child: PostItCard(
                note: note,
                layout: layout,
                showPin: false,
                enableHero: false,
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

    await pumpCard(PostItCardLayout.grid);
    expect(
      find.byKey(const ValueKey('grid-attachment-note-attachment')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('attachment-preview-attachment-1')),
      findsNothing,
    );
    expect(find.text('comprobante.pdf'), findsNothing);

    await pumpCard(PostItCardLayout.large);
    expect(
      find.byKey(const ValueKey('grid-attachment-note-attachment')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('attachment-preview-attachment-1')),
      findsOneWidget,
    );
    expect(find.text('comprobante.pdf'), findsOneWidget);
  });

  testWidgets('editor restores custom responsible and attached PDF', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 12);
    final note = Note(
      id: 'note-money',
      boardId: 'board-1',
      title: r'$5.000',
      content: '',
      color: NoteColor.green,
      authorName: 'Nico',
      customAssigneeName: 'Camila',
      attachment: const NoteAttachment(
        id: 'attachment-1',
        name: 'comprobante.pdf',
        mimeType: 'application/pdf',
        sizeBytes: 128,
      ),
      category: NoteCategory.money,
      isCompleted: false,
      positionX: 0,
      positionY: 0,
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteEditorSheet(
            note: note,
            defaultAuthorName: 'Nico',
            showAuthorField: false,
          ),
        ),
      ),
    );

    final responsible = tester.widget<TextFormField>(
      find.byKey(const ValueKey('note-custom-assignee-field')),
    );
    expect(responsible.controller?.text, 'Camila');
    expect(find.text('comprobante.pdf'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('remove-note-attachment-button')),
      findsOneWidget,
    );
    expect(find.text('Monto (CLP)'), findsOneWidget);
  });

  testWidgets('shows two local photo thumbnails and enforces the limit', (
    tester,
  ) async {
    const onePixelPng =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+'
        'A8AAQUBAScY42YAAAAASUVORK5CYII=';
    final now = DateTime.utc(2026, 8, 12);
    final note = Note(
      id: 'note-two-photos',
      boardId: 'board-1',
      title: 'Dos fotos',
      content: '',
      color: NoteColor.yellow,
      authorName: 'Nico',
      attachments: const [
        NoteAttachment(
          id: 'photo-1',
          name: 'foto-1.png',
          mimeType: 'image/png',
          sizeBytes: 68,
          dataBase64: onePixelPng,
        ),
        NoteAttachment(
          id: 'photo-2',
          name: 'foto-2.png',
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
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 520,
            child: PostItCard(
              note: note,
              layout: PostItCardLayout.large,
              showPin: false,
              enableHero: false,
              onToggle: () {},
              onPin: () {},
              onOpen: () {},
              onChecklistToggle: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('attachment-image-photo-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('attachment-image-photo-2')),
      findsOneWidget,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteEditorSheet(
            note: note,
            defaultAuthorName: 'Nico',
            showAuthorField: false,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('note-editor-photo-photo-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('note-editor-photo-photo-2')),
      findsOneWidget,
    );
    expect(find.text('Fotos · 2/2'), findsOneWidget);
    expect(find.byKey(const ValueKey('add-note-photo-button')), findsNothing);
  });
}
