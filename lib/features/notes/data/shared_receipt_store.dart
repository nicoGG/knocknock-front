import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:nocknock/features/notes/data/e2ee_crypto.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/presentation/note_attachment_picker.dart';

/// Pending shares outlive the provider's temporary file permission. Keep only
/// their opaque IDs in preferences and never delete the sender's original.
class SharedReceiptStore {
  SharedReceiptStore({
    SecureKeyValueStore? keys,
    this.directory = getApplicationSupportDirectory,
  }) : _keys = keys ?? FlutterSecureKeyValueStore();
  final SecureKeyValueStore _keys;
  final Future<Directory> Function() directory;
  final _cipher = AesGcm.with256bits();

  Future<File> _file(String id) async {
    if (!RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(id)) throw const FormatException();
    return File('${(await directory()).path}/pending-receipts/$id');
  }

  Future<void> stage(String id, String path) async {
    final source = XFile(
      path.startsWith('file://') ? Uri.parse(path).toFilePath() : path,
    );
    final prefix = await source.openRead(0, 5).expand((v) => v).toList();
    final pdf = ascii.decode(prefix, allowInvalid: true) == '%PDF-';
    if ((pdf || source.name.toLowerCase().endsWith('.pdf')) &&
        await source.length() > notePdfMaxBytes) {
      throw const NoteAttachmentPickFailure('El PDF puede pesar hasta 5 MB.');
    }
    final attachment = pdf || source.name.toLowerCase().endsWith('.pdf')
        ? createNotePdfAttachment(
            name: source.name,
            bytes: await source.readAsBytes(),
          )
        : await createNotePhotoAttachment(source);
    final key = await _cipher.newSecretKey();
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(attachment.toJson())),
      secretKey: key,
    );
    final file = await _file(id);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(box.concatenation(), flush: true);
    await _keys.write('receipt.$id', base64Encode(await key.extractBytes()));
  }

  Future<NoteAttachment> read(String id) async {
    final key = await _keys.read('receipt.$id');
    if (key == null) throw const FormatException();
    final box = SecretBox.fromConcatenation(
      await (await _file(id)).readAsBytes(),
      nonceLength: _cipher.nonceLength,
      macLength: _cipher.macAlgorithm.macLength,
    );
    final bytes = await _cipher.decrypt(
      box,
      secretKey: SecretKey(base64Decode(key)),
    );
    return NoteAttachment.fromJson(
      jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
    );
  }

  Future<void> remove(String id) async {
    final file = await _file(id);
    if (await file.exists()) await file.delete();
    await _keys.delete('receipt.$id');
  }
}
