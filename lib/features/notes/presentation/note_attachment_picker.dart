import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as image_tools;
import 'package:image_picker/image_picker.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:uuid/uuid.dart';

const noteAttachmentMaxCount = 2;
const noteAttachmentMaxBytes = 900_000;
const notePdfMaxBytes = 5 * 1024 * 1024;
const noteAttachmentMaxSourceBytes = 25 * 1024 * 1024;

class NoteAttachmentPickFailure implements Exception {
  const NoteAttachmentPickFailure(this.message);
  final String message;
}

enum NoteAttachmentSource { photos, pdf }

Future<List<NoteAttachment>> pickNoteAttachments({
  required BuildContext context,
  int remaining = noteAttachmentMaxCount,
}) async {
  if (remaining <= 0) return const [];
  final source = await showModalBottomSheet<NoteAttachmentSource>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const ValueKey('pick-note-photos'),
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Fotos'),
            subtitle: const Text('Se comprimen automáticamente'),
            onTap: () =>
                Navigator.pop(sheetContext, NoteAttachmentSource.photos),
          ),
          ListTile(
            key: const ValueKey('pick-note-pdf'),
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('Documento PDF'),
            subtitle: const Text('Máximo 5 MB'),
            onTap: () => Navigator.pop(sheetContext, NoteAttachmentSource.pdf),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted || source == null) return const [];
  if (source == NoteAttachmentSource.photos) {
    return pickNotePhotos(remaining: remaining);
  }
  final attachment = await pickNotePdf();
  return attachment == null ? const [] : [attachment];
}

Future<NoteAttachment?> pickNotePdf({FilePicker? filePicker}) async {
  final result = await (filePicker ?? FilePicker.platform).pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
    allowMultiple: false,
    withData: true,
  );
  final file = result?.files.singleOrNull;
  if (file == null) return null;
  final bytes = file.bytes;
  return createNotePdfAttachment(name: file.name, bytes: bytes);
}

@visibleForTesting
NoteAttachment createNotePdfAttachment({
  required String name,
  required Uint8List? bytes,
}) {
  if (bytes == null || bytes.isEmpty) {
    throw const NoteAttachmentPickFailure(
      'No pudimos leer ese PDF. Intenta elegirlo nuevamente.',
    );
  }
  if (bytes.length < 5 ||
      !listEquals(bytes.sublist(0, 5), ascii.encode('%PDF-'))) {
    throw const NoteAttachmentPickFailure(
      'El archivo seleccionado no es un PDF válido.',
    );
  }
  if (bytes.length > notePdfMaxBytes) {
    throw const NoteAttachmentPickFailure('El PDF puede pesar hasta 5 MB.');
  }
  final normalizedName = name.trim();
  return NoteAttachment(
    id: const Uuid().v4(),
    name: normalizedName.isEmpty
        ? 'Documento.pdf'
        : normalizedName.length <= 120
        ? normalizedName
        : normalizedName.substring(normalizedName.length - 120),
    mimeType: 'application/pdf',
    sizeBytes: bytes.length,
    dataBase64: base64Encode(bytes),
  );
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
    final sourceBytes = await file.readAsBytes();
    if (sourceBytes.isEmpty) {
      throw const NoteAttachmentPickFailure(
        'No pudimos leer esa foto. Intenta elegirla nuevamente.',
      );
    }
    if (sourceBytes.length > noteAttachmentMaxSourceBytes) {
      throw const NoteAttachmentPickFailure(
        'La foto original puede pesar hasta 25 MB.',
      );
    }
    final wasCompressed = sourceBytes.length > noteAttachmentMaxBytes;
    final bytes = wasCompressed
        ? await compute(compressNotePhoto, sourceBytes)
        : sourceBytes;
    if (bytes == null || bytes.length > noteAttachmentMaxBytes) {
      throw const NoteAttachmentPickFailure(
        'No pudimos comprimir esa foto. Prueba con otra imagen.',
      );
    }
    final normalizedName = file.name.trim();
    final extension = normalizedName.contains('.')
        ? normalizedName.split('.').last.toLowerCase()
        : '';
    final mimeType = wasCompressed
        ? 'image/jpeg'
        : switch (file.mimeType?.toLowerCase()) {
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
    final storedName = wasCompressed
        ? _replaceImageExtension(normalizedName, 'jpg')
        : normalizedName;
    attachments.add(
      NoteAttachment(
        id: const Uuid().v4(),
        name: storedName.isEmpty
            ? 'Foto.jpg'
            : storedName.length <= 120
            ? storedName
            : storedName.substring(storedName.length - 120),
        mimeType: mimeType,
        sizeBytes: bytes.length,
        dataBase64: base64Encode(bytes),
      ),
    );
  }
  return attachments;
}

@visibleForTesting
Uint8List? compressNotePhoto(Uint8List sourceBytes) {
  final decoded = image_tools.decodeImage(sourceBytes);
  if (decoded == null) return null;
  final source = image_tools.bakeOrientation(decoded);
  Uint8List? smallest;
  for (final maximumSide in const [1280, 1120, 960, 800, 640]) {
    final scale = math.min(
      1.0,
      maximumSide / math.max(source.width, source.height),
    );
    final resized = scale < 1
        ? image_tools.copyResize(
            source,
            width: math.max(1, (source.width * scale).round()),
            height: math.max(1, (source.height * scale).round()),
            interpolation: image_tools.Interpolation.average,
          )
        : source;
    for (final quality in const [72, 64, 56, 48, 40]) {
      final encoded = Uint8List.fromList(
        image_tools.encodeJpg(resized, quality: quality),
      );
      if (smallest == null || encoded.length < smallest.length) {
        smallest = encoded;
      }
      if (encoded.length <= noteAttachmentMaxBytes) return encoded;
    }
  }
  return smallest;
}

String _replaceImageExtension(String name, String extension) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'Foto.$extension';
  final dot = trimmed.lastIndexOf('.');
  final base = dot > 0 ? trimmed.substring(0, dot) : trimmed;
  return '$base.$extension';
}

/// Compatibility helper for callers that still request a single selection.
Future<NoteAttachment?> pickNoteAttachment() async =>
    (await pickNotePhotos(remaining: 1)).firstOrNull;
