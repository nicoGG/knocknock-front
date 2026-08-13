import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/data/e2ee_account_recovery.dart';

void main() {
  test(
    'persists one recovery identity in the private Drive app folder',
    () async {
      final drive = _MemoryDriveAppDataClient();
      final firstStore = GoogleDriveE2eeAccountRecoveryIdentityStore(
        client: drive,
      );
      final secondStore = GoogleDriveE2eeAccountRecoveryIdentityStore(
        client: drive,
      );

      final first = await firstStore.loadOrCreateIdentity('firebase-user-1');
      final second = await secondStore.loadOrCreateIdentity('firebase-user-1');

      expect(first, isNotNull);
      expect(second!.deviceId, first!.deviceId);
      expect(await second.publicKeyEncoded(), await first.publicKeyEncoded());
      expect(drive.createdFiles, 1);
      expect(drive.contents.values.single, isNot(contains('firebase-user-1')));
    },
  );

  test(
    'does not rotate recovery identity when the cloud copy is corrupt',
    () async {
      final drive = _MemoryDriveAppDataClient()
        ..addRawFile(
          GoogleDriveE2eeAccountRecoveryIdentityStore.fileName,
          '{invalid-json',
        );
      final store = GoogleDriveE2eeAccountRecoveryIdentityStore(client: drive);

      await expectLater(
        store.loadOrCreateIdentity('firebase-user-1'),
        throwsFormatException,
      );
      expect(drive.createdFiles, 0);
    },
  );

  test('binds a recovery identity to the matching Firebase user', () async {
    final drive = _MemoryDriveAppDataClient();
    final store = GoogleDriveE2eeAccountRecoveryIdentityStore(client: drive);
    await store.loadOrCreateIdentity('firebase-user-1');

    await expectLater(
      store.loadOrCreateIdentity('firebase-user-2'),
      throwsFormatException,
    );
    expect(drive.createdFiles, 1);
  });
}

class _MemoryDriveAppDataClient implements GoogleDriveAppDataClient {
  final contents = <String, String>{};
  final names = <String, String>{};
  final createdAt = <String, DateTime>{};
  int createdFiles = 0;

  void addRawFile(String name, String contents) {
    final id = 'file-${this.contents.length + 1}';
    this.contents[id] = contents;
    names[id] = name;
    createdAt[id] = DateTime.utc(
      2026,
      8,
      12,
    ).add(Duration(seconds: this.contents.length));
  }

  @override
  Future<void> createFile({
    required String name,
    required String contents,
  }) async {
    createdFiles++;
    addRawFile(name, contents);
  }

  @override
  Future<List<GoogleDriveAppDataFile>> listFiles(String name) async {
    final files = names.entries
        .where((entry) => entry.value == name)
        .map(
          (entry) => GoogleDriveAppDataFile(
            id: entry.key,
            createdAt: createdAt[entry.key]!,
          ),
        )
        .toList();
    files.sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return files;
  }

  @override
  Future<String> readFile(String id) async => contents[id]!;
}
