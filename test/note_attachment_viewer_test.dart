import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/presentation/note_attachment_download.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_pdf_viewer.dart';
import 'package:nocknock/features/notes/presentation/widgets/post_it_card.dart';

void main() {
  test('normalizes attachment download names and decodes their bytes', () {
    final attachment = NoteAttachment(
      id: 'pdf-1',
      name: r'../comprobante:agosto?.pdf',
      mimeType: 'application/pdf',
      sizeBytes: 8,
      dataBase64: base64Encode(const [37, 80, 68, 70, 45, 49, 46, 52]),
    );

    expect(noteAttachmentDownloadName(attachment), 'comprobante_agosto_.pdf');
    expect(
      decodeNoteAttachmentBytes(attachment).take(4),
      orderedEquals([37, 80, 68, 70]),
    );
  });

  testWidgets('loads a remote PDF, displays it, and saves its bytes', (
    tester,
  ) async {
    final pdfBytes = Uint8List.fromList('%PDF-1.4 test'.codeUnits);
    const metadata = NoteAttachment(
      id: 'pdf-remote',
      name: 'comprobante.pdf',
      mimeType: 'application/pdf',
      sizeBytes: 13,
    );
    NoteAttachment? savedAttachment;
    Uint8List? savedBytes;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showNotePdfViewer(
              context,
              attachment: metadata,
              loader: (_) async =>
                  metadata.copyWith(dataBase64: base64Encode(pdfBytes)),
              pdfViewBuilder: (bytes, sourceName) =>
                  Center(child: Text('$sourceName · ${bytes.length} bytes')),
              saver: (attachment, bytes) async {
                savedAttachment = attachment;
                savedBytes = bytes;
                return '/Descargas/${attachment.name}';
              },
            ),
            child: const Text('Abrir PDF'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir PDF'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('pdf-attachment-viewer')), findsOneWidget);
    expect(find.text('comprobante.pdf · 13 bytes'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('download-pdf-pdf-remote')));
    await tester.pump();

    expect(savedAttachment?.id, 'pdf-remote');
    expect(savedBytes, pdfBytes);
    expect(find.text('PDF guardado en el dispositivo'), findsOneWidget);
  });

  testWidgets('saves the current photo from the fullscreen viewer', (
    tester,
  ) async {
    const onePixelPng =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+'
        'A8AAQUBAScY42YAAAAASUVORK5CYII=';
    const photo = NoteAttachment(
      id: 'photo-download',
      name: 'paseo.png',
      mimeType: 'image/png',
      sizeBytes: 68,
      dataBase64: onePixelPng,
    );
    NoteAttachment? savedAttachment;
    Uint8List? savedBytes;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showNotePhotoViewer(
              context,
              attachments: const [photo],
              initialIndex: 0,
              loader: null,
              saver: (attachment, bytes) async {
                savedAttachment = attachment;
                savedBytes = bytes;
                return '/Descargas/${attachment.name}';
              },
            ),
            child: const Text('Abrir foto'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir foto'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('download-photo-photo-download')),
    );
    await tester.pump();

    expect(savedAttachment, photo);
    expect(savedBytes, isNotEmpty);
    expect(find.text('Foto guardada en el dispositivo'), findsOneWidget);
  });
}
