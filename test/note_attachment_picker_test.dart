import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_tools;
import 'package:nocknock/features/notes/presentation/note_attachment_picker.dart';

void main() {
  test('creates a PDF attachment for encryption and persistence', () {
    final bytes = Uint8List.fromList('%PDF-1.7\n%%EOF'.codeUnits);

    final attachment = createNotePdfAttachment(
      name: 'comprobante.pdf',
      bytes: bytes,
    );

    expect(attachment.name, 'comprobante.pdf');
    expect(attachment.mimeType, 'application/pdf');
    expect(attachment.sizeBytes, bytes.length);
    expect(attachment.dataBase64, isNotEmpty);
  });

  test('rejects a renamed non-PDF file', () {
    expect(
      () => createNotePdfAttachment(
        name: 'falso.pdf',
        bytes: Uint8List.fromList('no es pdf'.codeUnits),
      ),
      throwsA(isA<NoteAttachmentPickFailure>()),
    );
  });

  test('accepts PDFs up to 5 MB and rejects larger documents', () {
    final maximumPdf = Uint8List(notePdfMaxBytes)
      ..setRange(0, 5, '%PDF-'.codeUnits);
    expect(
      createNotePdfAttachment(name: 'grande.pdf', bytes: maximumPdf).sizeBytes,
      notePdfMaxBytes,
    );

    final oversizedPdf = Uint8List(notePdfMaxBytes + 1)
      ..setRange(0, 5, '%PDF-'.codeUnits);
    expect(
      () =>
          createNotePdfAttachment(name: 'muy-grande.pdf', bytes: oversizedPdf),
      throwsA(isA<NoteAttachmentPickFailure>()),
    );
  });

  test('compresses a detailed photo to the encrypted attachment limit', () {
    final image = image_tools.Image(width: 1800, height: 1800);
    var value = 0x12345678;
    for (final pixel in image) {
      value = (1664525 * value + 1013904223) & 0xFFFFFFFF;
      pixel
        ..r = value & 0xFF
        ..g = (value >> 8) & 0xFF
        ..b = (value >> 16) & 0xFF
        ..a = 255;
    }
    final source = Uint8List.fromList(image_tools.encodePng(image));
    expect(source.length, greaterThan(3 * 1024 * 1024));

    final compressed = compressNotePhoto(source);

    expect(compressed, isNotNull);
    expect(compressed!.length, lessThanOrEqualTo(noteAttachmentMaxBytes));
    final decoded = image_tools.decodeJpg(compressed);
    expect(decoded, isNotNull);
    expect(decoded!.width, lessThanOrEqualTo(1280));
    expect(decoded.height, lessThanOrEqualTo(1280));
  });
}
