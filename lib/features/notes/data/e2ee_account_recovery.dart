import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:nocknock/features/notes/data/e2ee_crypto.dart';
import 'package:uuid/uuid.dart';

abstract interface class E2eeAccountRecoveryIdentityStore {
  /// Returns an account-scoped identity, or null when cloud authorization is
  /// unavailable. The private key never passes through the NockNock backend.
  Future<E2eeDeviceIdentity?> loadOrCreateIdentity(String userId);
}

class GoogleDriveAppDataFile {
  const GoogleDriveAppDataFile({required this.id, required this.createdAt});

  final String id;
  final DateTime createdAt;
}

abstract interface class GoogleDriveAppDataClient {
  Future<List<GoogleDriveAppDataFile>> listFiles(String name);

  Future<String> readFile(String id);

  Future<void> createFile({required String name, required String contents});
}

typedef GoogleAuthorizationHeadersProvider =
    Future<Map<String, String>?> Function();

class DioGoogleDriveAppDataClient implements GoogleDriveAppDataClient {
  DioGoogleDriveAppDataClient({
    required this.authorizationHeadersProvider,
    Dio? dio,
  }) : _dio = dio ?? Dio();

  static const _filesUrl = 'https://www.googleapis.com/drive/v3/files';
  static const _uploadUrl = 'https://www.googleapis.com/upload/drive/v3/files';

  final GoogleAuthorizationHeadersProvider authorizationHeadersProvider;
  final Dio _dio;

  @override
  Future<List<GoogleDriveAppDataFile>> listFiles(String name) async {
    final headers = await _requireHeaders();
    final escapedName = name.replaceAll("'", r"\'");
    final response = await _dio.get<Map<String, dynamic>>(
      _filesUrl,
      queryParameters: {
        'spaces': 'appDataFolder',
        'q': "name = '$escapedName' and trashed = false",
        'fields': 'files(id,createdTime)',
        'orderBy': 'createdTime asc',
        'pageSize': 100,
      },
      options: Options(headers: headers),
    );
    final files = response.data?['files'];
    if (files is! List) return const [];
    final result = <GoogleDriveAppDataFile>[];
    for (final value in files) {
      if (value is! Map) continue;
      final item = Map<String, dynamic>.from(value);
      final id = item['id'];
      final createdAt = DateTime.tryParse(item['createdTime'] as String? ?? '');
      if (id is String && id.isNotEmpty && createdAt != null) {
        result.add(GoogleDriveAppDataFile(id: id, createdAt: createdAt));
      }
    }
    result.sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return result;
  }

  @override
  Future<String> readFile(String id) async {
    final headers = await _requireHeaders();
    final response = await _dio.get<String>(
      '$_filesUrl/${Uri.encodeComponent(id)}',
      queryParameters: const {'alt': 'media'},
      options: Options(headers: headers, responseType: ResponseType.plain),
    );
    return response.data ?? '';
  }

  @override
  Future<void> createFile({
    required String name,
    required String contents,
  }) async {
    final headers = await _requireHeaders();
    final metadata = await _dio.post<Map<String, dynamic>>(
      _filesUrl,
      data: {
        'name': name,
        'parents': const ['appDataFolder'],
        'mimeType': 'application/json',
      },
      queryParameters: const {'fields': 'id'},
      options: Options(headers: headers),
    );
    final id = metadata.data?['id'];
    if (id is! String || id.isEmpty) {
      throw StateError('Google Drive no devolvió el archivo creado');
    }
    await _dio.patch<void>(
      '$_uploadUrl/${Uri.encodeComponent(id)}',
      data: utf8.encode(contents),
      queryParameters: const {'uploadType': 'media'},
      options: Options(
        headers: headers,
        contentType: 'application/json; charset=utf-8',
      ),
    );
  }

  Future<Map<String, String>> _requireHeaders() async {
    final headers = await authorizationHeadersProvider();
    if (headers == null || headers['Authorization']?.isNotEmpty != true) {
      throw const GoogleDriveAuthorizationUnavailable();
    }
    return headers;
  }
}

class GoogleDriveAuthorizationUnavailable implements Exception {
  const GoogleDriveAuthorizationUnavailable();
}

class GoogleDriveE2eeAccountRecoveryIdentityStore
    implements E2eeAccountRecoveryIdentityStore {
  GoogleDriveE2eeAccountRecoveryIdentityStore({
    required this.client,
    X25519? x25519,
    Sha256? sha256,
  }) : _x25519 = x25519 ?? X25519(),
       _sha256 = sha256 ?? Sha256();

  static const fileName = 'nocknock-e2ee-account-recovery-v1.json';

  final GoogleDriveAppDataClient client;
  final X25519 _x25519;
  final Sha256 _sha256;

  @override
  Future<E2eeDeviceIdentity?> loadOrCreateIdentity(String userId) async {
    final userBinding = await _userBinding(userId);
    final existingFiles = await client.listFiles(fileName);
    final existing = await _findIdentity(existingFiles, userBinding);
    if (existing != null) return existing;
    if (existingFiles.isNotEmpty) {
      throw const FormatException(
        'La identidad de recuperación de la cuenta está dañada',
      );
    }

    final candidate = await _newIdentity();
    await client.createFile(
      name: fileName,
      contents: await _encodeIdentity(candidate, userBinding),
    );

    // Two devices may create the first backup concurrently. Re-reading the
    // oldest valid file makes both converge before either identity registers.
    final filesAfterCreate = await client.listFiles(fileName);
    return await _findIdentity(filesAfterCreate, userBinding) ?? candidate;
  }

  Future<E2eeDeviceIdentity?> _findIdentity(
    List<GoogleDriveAppDataFile> files,
    String userBinding,
  ) async {
    for (final file in files) {
      try {
        final identity = await _decodeIdentity(
          await client.readFile(file.id),
          userBinding,
        );
        if (identity != null) return identity;
      } on Object {
        // Ignore partial/corrupt duplicates and continue with the next file.
      }
    }
    return null;
  }

  Future<E2eeDeviceIdentity> _newIdentity() async {
    final generated = await _x25519.newKeyPair();
    final privateKey = await generated.extractPrivateKeyBytes();
    final publicKey = await generated.extractPublicKey();
    return E2eeDeviceIdentity(
      deviceId: const Uuid().v4(),
      keyPair: SimpleKeyPairData(
        privateKey,
        publicKey: publicKey,
        type: KeyPairType.x25519,
      ),
    );
  }

  Future<String> _encodeIdentity(
    E2eeDeviceIdentity identity,
    String userBinding,
  ) async {
    final privateKey = await identity.keyPair.extractPrivateKeyBytes();
    final publicKey = await identity.keyPair.extractPublicKey();
    return jsonEncode({
      'version': 1,
      'userBinding': userBinding,
      'deviceId': identity.deviceId,
      'privateKey': encodeBase64Url(privateKey),
      'publicKey': encodeBase64Url(publicKey.bytes),
    });
  }

  Future<E2eeDeviceIdentity?> _decodeIdentity(
    String contents,
    String expectedUserBinding,
  ) async {
    final value = jsonDecode(contents);
    if (value is! Map) return null;
    final json = Map<String, dynamic>.from(value);
    if (json['version'] != 1 ||
        json['userBinding'] != expectedUserBinding ||
        json['deviceId'] is! String ||
        json['privateKey'] is! String ||
        json['publicKey'] is! String) {
      return null;
    }
    final deviceId = json['deviceId'] as String;
    final privateKey = decodeBase64Url(json['privateKey'] as String);
    final publicKey = decodeBase64Url(json['publicKey'] as String);
    if (deviceId.length < 8 ||
        deviceId.length > 128 ||
        privateKey.length != 32 ||
        publicKey.length != 32) {
      return null;
    }
    final derived = await _x25519.newKeyPairFromSeed(privateKey);
    final derivedPublicKey = await derived.extractPublicKey();
    if (!_sameBytes(publicKey, derivedPublicKey.bytes)) return null;
    return E2eeDeviceIdentity(
      deviceId: deviceId,
      keyPair: SimpleKeyPairData(
        privateKey,
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.x25519),
        type: KeyPairType.x25519,
      ),
    );
  }

  Future<String> _userBinding(String userId) async {
    final hash = await _sha256.hash(
      utf8.encode('nocknock-recovery-v1:$userId'),
    );
    return encodeBase64Url(hash.bytes);
  }

  bool _sameBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }
}
