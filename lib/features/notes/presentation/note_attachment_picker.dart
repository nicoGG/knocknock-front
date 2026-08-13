import 'dart:convert';

import 'package:image_picker/image_picker.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:uuid/uuid.dart';

const noteAttachmentMaxCount = 2;
const noteAttachmentMaxBytes = 900_000;

class NoteAttachmentPickFailure implements Exception {
  const NoteAttachmentPickFailure(this.message);
  final String message;
}

/// Selects small, display-ready photos instead of persisting camera originals.
/// The picker performs the resize/compression before bytes are encrypted and
/// uploaded, so both the local cache and MongoDB receive the optimized copy.
Future<List<NoteAttachment>> pickNotePhotos({
  int remaining = noteAttachmentMaxCount,
  ImagePicker? imagePicker,
}) async {
  if (remaining <= 0) return const [];
  final files = await (imagePicker ?? ImagePicker()).pickMultiImage(
    maxWidth: 1280,
    maxHeight: 1280,
    imageQuality: 70,
    limit: remaining.clamp(1, noteAttachmentMaxCount),
    requestFullMetadata: false,
  );
  final attachments = <NoteAttachment>[];
  for (final file in files.take(remaining)) {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw const NoteAttachmentPickFailure(
        'No pudimos leer esa foto. Intenta elegirla nuevamente.',
      );
    }
    if (bytes.length > noteAttachmentMaxBytes) {
      throw const NoteAttachmentPickFailure(
        'No pudimos reducir una foto lo suficiente. Prueba con otra imagen.',
      );
    }
    final normalizedName = file.name.trim();
    final extension = normalizedName.contains('.')
        ? normalizedName.split('.').last.toLowerCase()
        : '';
    final mimeType = switch (file.mimeType?.toLowerCase()) {
      'image/jpeg' => 'image/jpeg',
      'image/png' => 'image/png',
      'image/webp' => 'image/webp',
      'image/heic' => 'image/heic',
      'image/heif' => 'image/heif',
      _ => switch (extension) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        'heic' => 'image/heic',
        'heif' => 'image/heif',
        _ => throw const NoteAttachmentPickFailure(
          'Solo puedes agregar fotos JPG, PNG, WebP o HEIC.',
        ),
      },
    };
    attachments.add(
      NoteAttachment(
        id: const Uuid().v4(),
        name: normalizedName.isEmpty
            ? 'Foto.jpg'
            : normalizedName.length <= 120
            ? normalizedName
            : normalizedName.substring(normalizedName.length - 120),
        mimeType: mimeType,
        sizeBytes: bytes.length,
        dataBase64: base64Encode(bytes),
      ),
    );
  }
  return attachments;
}

/// Compatibility helper for callers that still request a single selection.
Future<NoteAttachment?> pickNoteAttachment() async =>
    (await pickNotePhotos(remaining: 1)).firstOrNull;
