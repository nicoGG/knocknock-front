import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:uuid/uuid.dart';

const noteAttachmentMaxBytes = 3_000_000;

class NoteAttachmentPickFailure implements Exception {
  const NoteAttachmentPickFailure(this.message);
  final String message;
}

Future<NoteAttachment?> pickNoteAttachment() async {
  const acceptedFiles = XTypeGroup(
    label: 'Imágenes o PDF',
    extensions: ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'pdf'],
    mimeTypes: [
      'image/jpeg',
      'image/png',
      'image/webp',
      'image/heic',
      'image/heif',
      'application/pdf',
    ],
    uniformTypeIdentifiers: [
      'public.jpeg',
      'public.png',
      'org.webmproject.webp',
      'public.heic',
      'public.heif',
      'com.adobe.pdf',
    ],
  );
  final file = await openFile(acceptedTypeGroups: [acceptedFiles]);
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  if (bytes.isEmpty) {
    throw const NoteAttachmentPickFailure(
      'No pudimos leer ese archivo. Intenta elegirlo nuevamente.',
    );
  }
  if (bytes.length > noteAttachmentMaxBytes) {
    throw const NoteAttachmentPickFailure('El adjunto puede pesar hasta 3 MB.');
  }
  final normalizedName = file.name.trim();
  final extension = normalizedName.contains('.')
      ? normalizedName.split('.').last.toLowerCase()
      : '';
  final mimeType = switch (extension) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'heif' => 'image/heif',
    'pdf' => 'application/pdf',
    _ => throw const NoteAttachmentPickFailure(
      'Solo puedes adjuntar PDF o imágenes.',
    ),
  };
  return NoteAttachment(
    id: const Uuid().v4(),
    name: normalizedName.length <= 120
        ? normalizedName
        : normalizedName.substring(normalizedName.length - 120),
    mimeType: mimeType,
    sizeBytes: bytes.length,
    dataBase64: base64Encode(bytes),
  );
}
