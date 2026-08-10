import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

const e2eeCiphertextPrefix = 'e2ee:v1:';
const e2eeKeyEnvelopePrefix = 'e2ee-key:v1:';
const e2eeListNameField = 'list:name:v1';
const e2eeNoteTitleField = 'note:title:v1';

abstract interface class SecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  FlutterSecureKeyValueStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class E2eeDeviceIdentity {
  const E2eeDeviceIdentity({required this.deviceId, required this.keyPair});

  final String deviceId;
  final SimpleKeyPairData keyPair;

  Future<String> publicKeyEncoded() async {
    final publicKey = await keyPair.extractPublicKey();
    return encodeBase64Url(publicKey.bytes);
  }
}

class E2eeKeyStore {
  E2eeKeyStore({SecureKeyValueStore? storage, X25519? x25519})
    : _storage = storage ?? FlutterSecureKeyValueStore(),
      _x25519 = x25519 ?? X25519();

  final SecureKeyValueStore _storage;
  final X25519 _x25519;

  Future<E2eeDeviceIdentity> loadOrCreateIdentity(String userId) async {
    final prefix = _identityPrefix(userId);
    final storedDeviceId = await _storage.read('$prefix.device');
    final storedPrivateKey = await _storage.read('$prefix.private');
    final storedPublicKey = await _storage.read('$prefix.public');
    if (storedDeviceId != null &&
        storedPrivateKey != null &&
        storedPublicKey != null) {
      final privateBytes = decodeBase64Url(storedPrivateKey);
      final publicBytes = decodeBase64Url(storedPublicKey);
      if (privateBytes.length != 32 || publicBytes.length != 32) {
        throw const FormatException('La identidad cifrada local está dañada');
      }
      return E2eeDeviceIdentity(
        deviceId: storedDeviceId,
        keyPair: SimpleKeyPairData(
          privateBytes,
          publicKey: SimplePublicKey(publicBytes, type: KeyPairType.x25519),
          type: KeyPairType.x25519,
        ),
      );
    }
    if (storedDeviceId != null ||
        storedPrivateKey != null ||
        storedPublicKey != null) {
      throw const FormatException('La identidad cifrada local está incompleta');
    }

    final keyPair = await _x25519.newKeyPair();
    final privateBytes = await keyPair.extractPrivateKeyBytes();
    final publicKey = await keyPair.extractPublicKey();
    final identity = E2eeDeviceIdentity(
      deviceId: const Uuid().v4(),
      keyPair: SimpleKeyPairData(
        privateBytes,
        publicKey: publicKey,
        type: KeyPairType.x25519,
      ),
    );
    await _storage.write('$prefix.device', identity.deviceId);
    await _storage.write('$prefix.private', encodeBase64Url(privateBytes));
    await _storage.write('$prefix.public', encodeBase64Url(publicKey.bytes));
    return identity;
  }

  Future<SecretKey?> readListKey(String userId, String listId) async {
    final encoded = await _storage.read(_listKeyName(userId, listId));
    if (encoded == null) return null;
    final bytes = decodeBase64Url(encoded);
    if (bytes.length != 32) {
      throw const FormatException('La llave local de la lista está dañada');
    }
    return SecretKey(bytes);
  }

  Future<void> writeListKey(
    String userId,
    String listId,
    SecretKey secretKey,
  ) async {
    final bytes = await secretKey.extractBytes();
    await _storage.write(_listKeyName(userId, listId), encodeBase64Url(bytes));
  }

  Future<void> deleteListKey(String userId, String listId) =>
      _storage.delete(_listKeyName(userId, listId));

  String _identityPrefix(String userId) => 'nocknock.e2ee.v1.$userId';

  String _listKeyName(String userId, String listId) =>
      '${_identityPrefix(userId)}.list.$listId';
}

class E2eeCipher {
  E2eeCipher({AesGcm? aesGcm, X25519? x25519, Hkdf? hkdf})
    : _aesGcm = aesGcm ?? AesGcm.with256bits(),
      _x25519 = x25519 ?? X25519(),
      _hkdf = hkdf ?? Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  final AesGcm _aesGcm;
  final X25519 _x25519;
  final Hkdf _hkdf;

  static bool isCiphertext(String? value) {
    if (value == null || !value.startsWith(e2eeCiphertextPrefix)) return false;
    final parts = value.split(':');
    if (parts.length != 4 ||
        '${parts[0]}:${parts[1]}:' != e2eeCiphertextPrefix ||
        !_isBase64Url(parts[2]) ||
        !_isBase64Url(parts[3])) {
      return false;
    }
    try {
      return decodeBase64Url(parts[2]).length == 12 &&
          decodeBase64Url(parts[3]).length >= 16;
    } on Object {
      return false;
    }
  }

  Future<SecretKey> newListKey() => _aesGcm.newSecretKey();

  Future<String> encryptString(
    String clearText,
    SecretKey secretKey, {
    required String field,
  }) async {
    final nonce = _aesGcm.newNonce();
    final box = await _aesGcm.encrypt(
      utf8.encode(clearText),
      secretKey: secretKey,
      nonce: nonce,
      aad: utf8.encode(field),
    );
    return '$e2eeCiphertextPrefix${encodeBase64Url(nonce)}:'
        '${encodeBase64Url([...box.cipherText, ...box.mac.bytes])}';
  }

  Future<String> decryptString(
    String ciphertext,
    SecretKey secretKey, {
    required String field,
  }) async {
    final parts = ciphertext.split(':');
    if (parts.length != 4 ||
        '${parts[0]}:${parts[1]}:' != e2eeCiphertextPrefix) {
      throw const FormatException('El dato cifrado no tiene un formato válido');
    }
    final nonce = decodeBase64Url(parts[2]);
    final combined = decodeBase64Url(parts[3]);
    if (nonce.length != 12 || combined.length < 16) {
      throw const FormatException('El dato cifrado no tiene un formato válido');
    }
    final macOffset = combined.length - 16;
    final clearBytes = await _aesGcm.decrypt(
      SecretBox(
        combined.sublist(0, macOffset),
        nonce: nonce,
        mac: Mac(combined.sublist(macOffset)),
      ),
      secretKey: secretKey,
      aad: utf8.encode(field),
    );
    return utf8.decode(clearBytes);
  }

  Future<String> wrapListKey(
    SecretKey listKey,
    String recipientPublicKey,
  ) async {
    final recipientBytes = decodeBase64Url(recipientPublicKey);
    if (recipientBytes.length != 32) {
      throw const FormatException('La llave pública no es válida');
    }
    final recipient = SimplePublicKey(recipientBytes, type: KeyPairType.x25519);
    final ephemeral = await _x25519.newKeyPair();
    final ephemeralPublic = await ephemeral.extractPublicKey();
    final shared = await _x25519.sharedSecretKey(
      keyPair: ephemeral,
      remotePublicKey: recipient,
    );
    final wrappingKey = await _deriveWrappingKey(
      shared,
      ephemeralPublic.bytes,
      recipientBytes,
    );
    final nonce = _aesGcm.newNonce();
    final listKeyBytes = await listKey.extractBytes();
    final aad = [...ephemeralPublic.bytes, ...recipientBytes];
    final box = await _aesGcm.encrypt(
      listKeyBytes,
      secretKey: wrappingKey,
      nonce: nonce,
      aad: aad,
    );
    return '$e2eeKeyEnvelopePrefix${encodeBase64Url(ephemeralPublic.bytes)}:'
        '${encodeBase64Url(nonce)}:'
        '${encodeBase64Url([...box.cipherText, ...box.mac.bytes])}';
  }

  Future<SecretKey> unwrapListKey(
    String envelope,
    SimpleKeyPairData recipientKeyPair,
  ) async {
    final parts = envelope.split(':');
    if (parts.length != 5 ||
        '${parts[0]}:${parts[1]}:' != e2eeKeyEnvelopePrefix) {
      throw const FormatException('El sobre de llave no es válido');
    }
    final ephemeralBytes = decodeBase64Url(parts[2]);
    final nonce = decodeBase64Url(parts[3]);
    final combined = decodeBase64Url(parts[4]);
    if (ephemeralBytes.length != 32 ||
        nonce.length != 12 ||
        combined.length != 48) {
      throw const FormatException('El sobre de llave no es válido');
    }
    final recipientPublic = await recipientKeyPair.extractPublicKey();
    final shared = await _x25519.sharedSecretKey(
      keyPair: recipientKeyPair,
      remotePublicKey: SimplePublicKey(
        ephemeralBytes,
        type: KeyPairType.x25519,
      ),
    );
    final wrappingKey = await _deriveWrappingKey(
      shared,
      ephemeralBytes,
      recipientPublic.bytes,
    );
    final macOffset = combined.length - 16;
    final listKeyBytes = await _aesGcm.decrypt(
      SecretBox(
        combined.sublist(0, macOffset),
        nonce: nonce,
        mac: Mac(combined.sublist(macOffset)),
      ),
      secretKey: wrappingKey,
      aad: [...ephemeralBytes, ...recipientPublic.bytes],
    );
    if (listKeyBytes.length != 32) {
      throw const FormatException('La llave de lista no es válida');
    }
    return SecretKey(listKeyBytes);
  }

  Future<SecretKey> _deriveWrappingKey(
    SecretKey shared,
    List<int> ephemeralPublicKey,
    List<int> recipientPublicKey,
  ) => _hkdf.deriveKey(
    secretKey: shared,
    nonce: utf8.encode('nocknock-e2ee-envelope-v1'),
    info: [...ephemeralPublicKey, ...recipientPublicKey],
  );
}

String encodeBase64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

bool _isBase64Url(String value) =>
    value.isNotEmpty && RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value);

Uint8List decodeBase64Url(String value) {
  final padding = (4 - value.length % 4) % 4;
  final suffix = List.filled(padding, '=').join();
  return base64Url.decode('$value$suffix');
}
