import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/data/e2ee_crypto.dart';

void main() {
  test(
    'stores a stable device identity without exposing the private key',
    () async {
      final storage = _MemorySecureStore();
      final keyStore = E2eeKeyStore(storage: storage);

      final first = await keyStore.loadOrCreateIdentity('user-1');
      final second = await keyStore.loadOrCreateIdentity('user-1');

      expect(second.deviceId, first.deviceId);
      expect(await second.publicKeyEncoded(), await first.publicKeyEncoded());
      expect(storage.values.values, everyElement(isNotEmpty));
    },
  );

  test(
    'wraps a list key for one device and authenticates every field',
    () async {
      final cipher = E2eeCipher();
      final recipient = await X25519().newKeyPair();
      final recipientData = await recipient.extract();
      final recipientPublic = await recipient.extractPublicKey();
      final listKey = await cipher.newListKey();

      final envelope = await cipher.wrapListKey(
        listKey,
        encodeBase64Url(recipientPublic.bytes),
      );
      final unwrapped = await cipher.unwrapListKey(envelope, recipientData);
      final ciphertext = await cipher.encryptString(
        'Comprar pan',
        unwrapped,
        field: 'note:title:v1',
      );

      expect(envelope, startsWith(e2eeKeyEnvelopePrefix));
      expect(ciphertext, startsWith(e2eeCiphertextPrefix));
      expect(ciphertext, isNot(contains('Comprar pan')));
      await expectLater(
        cipher.decryptString(ciphertext, unwrapped, field: 'note:title:v1'),
        completion('Comprar pan'),
      );
      await expectLater(
        cipher.decryptString(ciphertext, unwrapped, field: 'note:content:v1'),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );

      final emptyCiphertext = await cipher.encryptString(
        '',
        unwrapped,
        field: 'note:content:v1',
      );
      expect(E2eeCipher.isCiphertext(emptyCiphertext), isTrue);
      await expectLater(
        cipher.decryptString(
          emptyCiphertext,
          unwrapped,
          field: 'note:content:v1',
        ),
        completion(isEmpty),
      );
    },
  );

  test('a different device cannot unwrap the list key', () async {
    final cipher = E2eeCipher();
    final intended = await X25519().newKeyPair();
    final other = await X25519().newKeyPair();
    final intendedPublic = await intended.extractPublicKey();
    final envelope = await cipher.wrapListKey(
      await cipher.newListKey(),
      encodeBase64Url(intendedPublic.bytes),
    );

    await expectLater(
      cipher.unwrapListKey(envelope, await other.extract()),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });
}

class _MemorySecureStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
