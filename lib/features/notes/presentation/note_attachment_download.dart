import 'dart:convert';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:nocknock/features/notes/domain/note.dart';

typedef NoteAttachmentSaver =
    Future<String?> Function(NoteAttachment attachment, Uint8List bytes);

Uint8List decodeNoteAttachmentBytes(NoteAttachment attachment) {
  final encoded = attachment.dataBase64?.trim();
  if (encoded == null || encoded.isEmpty) {
    throw const FormatException('El adjunto no contiene datos');
  }
  final bytes = base64Decode(encoded);
  if (bytes.isEmpty) {
    throw const FormatException('El adjunto está vacío');
  }
  return bytes;
}

Future<String?> saveNoteAttachmentToDevice(
  NoteAttachment attachment,
  Uint8List bytes,
) => FileSaver.instance.saveAs(
  name: noteAttachmentDownloadName(attachment),
  bytes: bytes,
  includeExtension: false,
  mimeType: MimeType.custom,
  customMimeType: attachment.mimeType,
);

@visibleForTesting
String noteAttachmentDownloadName(NoteAttachment attachment) {
  final leafName = attachment.name.trim().split(RegExp(r'[/\\]')).last;
  final sanitized = leafName
      .replaceAll(RegExp(r'[\x00-\x1F<>:"|?*]'), '_')
      .trim();
  if (sanitized.isNotEmpty && sanitized != '.' && sanitized != '..') {
    return sanitized;
  }
  return attachment.isPdf
      ? 'Documento.pdf'
      : 'Foto${_imageExtension(attachment)}';
}

String _imageExtension(NoteAttachment attachment) =>
    switch (attachment.mimeType) {
      'image/png' => '.png',
      'image/webp' => '.webp',
      'image/heic' => '.heic',
      'image/heif' => '.heif',
      _ => '.jpg',
    };
