import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/data/cached_notes_repository.dart';
import 'package:nocknock/features/notes/data/e2ee_crypto.dart';
import 'package:nocknock/features/notes/data/e2ee_notes_repository.dart';
import 'package:nocknock/features/notes/data/notes_repository.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('migrates legacy list data before returning readable content', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final remote = _FakeE2eeRemote();
    final repository = E2eeNotesRepository(
      repository: CachedNotesRepository(
        repository: remote,
        preferences: preferences,
        userIdProvider: () => 'user-1',
      ),
      userIdProvider: () => 'user-1',
      keyStore: E2eeKeyStore(storage: _MemorySecureStore()),
    );

    final lists = await repository.fetchLists();
    final notes = await repository.fetchNotes('home-user-1');

    expect(lists.single.name, 'Mis notas');
    expect(notes.single.title, 'Comprar pan');
    expect(notes.single.content, isEmpty);
    expect(remote.registeredDeviceId, isNotEmpty);
    expect(remote.rawList.encryption.version, 1);
    expect(remote.rawList.name, startsWith(e2eeCiphertextPrefix));
    expect(remote.rawList.name, isNot(contains('Mis notas')));
    expect(remote.rawNote.title, startsWith(e2eeCiphertextPrefix));
    expect(remote.rawNote.title, isNot(contains('Comprar pan')));
    expect(remote.rawNote.content, startsWith(e2eeCiphertextPrefix));
    await pumpEventQueue();
    final persisted = preferences.getString(CachedNotesRepository.storageKey);
    expect(persisted, contains(e2eeCiphertextPrefix));
    expect(persisted, isNot(contains('Mis notas')));
    expect(persisted, isNot(contains('Comprar pan')));

    repository.dispose();
  });

  test('shares the list key when a new recipient device registers', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final remote = _FakeE2eeRemote();
    final repository = E2eeNotesRepository(
      repository: CachedNotesRepository(
        repository: remote,
        preferences: preferences,
        userIdProvider: () => 'user-1',
      ),
      userIdProvider: () => 'user-1',
      keyStore: E2eeKeyStore(storage: _MemorySecureStore()),
    );
    final recipientIdentity = await E2eeKeyStore(
      storage: _MemorySecureStore(),
    ).loadOrCreateIdentity('user-2');

    await repository.fetchLists();
    remote.recipients = [
      EncryptionRecipient(
        userUid: 'user-2',
        deviceId: recipientIdentity.deviceId,
        publicKey: await recipientIdentity.publicKeyEncoded(),
        hasEnvelope: false,
      ),
    ];
    remote.emit(const ListKeyShareRequested('home-user-1'));
    await pumpEventQueue(times: 10);

    expect(remote.storedEnvelopes, hasLength(1));
    final sharedKey = await E2eeCipher().unwrapListKey(
      remote.storedEnvelopes.single.envelope,
      recipientIdentity.keyPair,
    );
    await expectLater(
      E2eeCipher().decryptString(
        remote.rawList.name,
        sharedKey,
        field: e2eeListNameField,
      ),
      completion('Mis notas'),
    );

    repository.dispose();
  });

  test(
    'encrypts custom aggregate board backgrounds before account sync',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final remote = _FakeE2eeRemote();
      final repository = E2eeNotesRepository(
        repository: CachedNotesRepository(
          repository: remote,
          preferences: preferences,
          userIdProvider: () => 'user-1',
        ),
        userIdProvider: () => 'user-1',
        keyStore: E2eeKeyStore(storage: _MemorySecureStore()),
      );
      await repository.fetchLists();
      const clearAppearance = ListAppearance(
        backgroundPreset: ListBackgroundPreset.custom,
        backgroundBlur: 2,
        customBackgroundImage: 'aW1hZ2UtYnl0ZXM=',
      );

      final saved = await repository.updateAggregateBoardAppearance(
        AggregateBoardScope.pinned,
        clearAppearance,
      );

      expect(saved.pinned, clearAppearance);
      expect(
        remote.aggregateBoardAppearances.pinned.customBackgroundImage,
        startsWith(e2eeCiphertextPrefix),
      );
      expect(
        remote.aggregateBoardAppearances.pinned.customBackgroundImage,
        isNot(contains(clearAppearance.customBackgroundImage!)),
      );
      expect(
        (await repository.fetchAggregateBoardAppearances()).pinned,
        clearAppearance,
      );

      repository.dispose();
    },
  );
}

class _FakeE2eeRemote extends Fake
    implements
        NotesRepository,
        E2eeNotesTransport,
        AggregateBoardAppearancesRepository {
  final _events = StreamController<NotesRealtimeEvent>.broadcast();
  final date = DateTime.utc(2026, 8, 10);
  String registeredDeviceId = '';
  List<EncryptionRecipient> recipients = const [];
  final storedEnvelopes = <_StoredEnvelope>[];
  AggregateBoardAppearances aggregateBoardAppearances =
      const AggregateBoardAppearances();

  late NoteList rawList = NoteList(
    id: 'home-user-1',
    name: 'Mis notas',
    createdAt: date,
    updatedAt: date,
  );
  late Note rawNote = Note(
    id: 'note-1',
    boardId: rawList.id,
    title: 'Comprar pan',
    content: '',
    color: NoteColor.yellow,
    authorName: 'Nico',
    isCompleted: false,
    positionX: 0,
    positionY: 0,
    createdAt: date,
    updatedAt: date,
  );

  @override
  Stream<NotesRealtimeEvent> get realtimeEvents => _events.stream;

  @override
  Future<void> registerEncryptionDevice({
    required String deviceId,
    required String publicKey,
  }) async {
    registeredDeviceId = deviceId;
    expect(publicKey, hasLength(43));
  }

  @override
  Future<List<NoteList>> fetchLists() async => [rawList];

  @override
  Future<List<Note>> fetchNotes(String boardId) async => [rawNote];

  @override
  Future<AggregateBoardAppearances> fetchAggregateBoardAppearances() async =>
      aggregateBoardAppearances;

  @override
  Future<AggregateBoardAppearances> updateAggregateBoardAppearance(
    AggregateBoardScope scope,
    ListAppearance appearance,
  ) async {
    aggregateBoardAppearances = aggregateBoardAppearances.copyWithScope(
      scope,
      appearance,
    );
    return aggregateBoardAppearances;
  }

  @override
  Future<Note> updateNote(String id, Map<String, dynamic> changes) async {
    rawNote = Note.fromJson({...rawNote.toJson(), ...changes});
    return rawNote;
  }

  @override
  Future<NoteList> enableListEncryption({
    required String listId,
    required String encryptedName,
    required String? encryptedCustomBackgroundImage,
    required ListKeyEnvelope keyEnvelope,
  }) async {
    rawList = rawList.copyWith(
      name: encryptedName,
      encryption: ListEncryption(version: 1, keyEnvelopes: [keyEnvelope]),
    );
    return rawList;
  }

  @override
  Future<List<EncryptionRecipient>> fetchEncryptionRecipients(
    String listId,
  ) async => recipients;

  @override
  Future<void> storeListKeyEnvelope({
    required String listId,
    required String recipientUid,
    required String deviceId,
    required String envelope,
  }) async {
    storedEnvelopes.add(
      _StoredEnvelope(
        listId: listId,
        recipientUid: recipientUid,
        deviceId: deviceId,
        envelope: envelope,
      ),
    );
  }

  void emit(NotesRealtimeEvent event) => _events.add(event);

  @override
  void dispose() {
    unawaited(_events.close());
  }
}

class _StoredEnvelope {
  const _StoredEnvelope({
    required this.listId,
    required this.recipientUid,
    required this.deviceId,
    required this.envelope,
  });

  final String listId;
  final String recipientUid;
  final String deviceId;
  final String envelope;
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
