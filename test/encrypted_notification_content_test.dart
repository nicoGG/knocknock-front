import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/data/e2ee_crypto.dart';
import 'package:nocknock/features/notifications/logic/encrypted_notification_content.dart';

void main() {
  test(
    'decrypts a note title only when the device owns the list key',
    () async {
      final storage = _MemorySecureStore();
      final keyStore = E2eeKeyStore(storage: storage);
      final cipher = E2eeCipher();
      final key = await cipher.newListKey();
      await keyStore.writeListKey('user-1', 'list-1', key);
      final encryptedTitle = await cipher.encryptString(
        'Comprar pan',
        key,
        field: e2eeNoteTitleField,
      );
      final resolver = EncryptedNotificationContentResolver(
        keyStore: keyStore,
        cipher: cipher,
      );
      final payload = {
        'boardId': 'list-1',
        'encryptedPreview': encryptedTitle,
        'previewField': 'noteTitle',
        'displayTitle': 'Recordatorio de NockNock',
        'displayBody': 'Abre NockNock para ver el recordatorio.',
      };

      final authorized = await resolver.resolve(payload, userId: 'user-1');
      final unauthorized = await resolver.resolve(payload, userId: 'user-2');

      expect(authorized.title, 'Recordatorio de NockNock');
      expect(authorized.body, 'Comprar pan');
      expect(unauthorized.body, 'Abre NockNock para ver el recordatorio.');
    },
  );
}

class _MemorySecureStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
