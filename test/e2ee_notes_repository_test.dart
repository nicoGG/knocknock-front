import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/data/cached_notes_repository.dart';
import 'package:nocknock/features/notes/data/e2ee_crypto.dart';
import 'package:nocknock/features/notes/data/e2ee_notes_repository.dart';
import 'package:nocknock/features/notes/data/notes_repository.dart';
import 'package:nocknock/features/notes/data/offline_mutation_store.dart';
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

  test(
    'encrypts a custom assignee and lazy attachment during migration',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final remote = _FakeE2eeRemote()
        ..initialCustomAssigneeName = 'Camila'
        ..attachmentPayload = const NoteAttachment(
          id: 'attachment-1',
          name: 'comprobante.png',
          mimeType: 'image/png',
          sizeBytes: 5,
          dataBase64: 'aG9sYQ==',
        );
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
      final note = (await repository.fetchNotes('home-user-1')).single;
      final attachment = await repository.fetchAttachment(note.id);

      expect(
        remote.rawNote.customAssigneeName,
        startsWith(e2eeCiphertextPrefix),
      );
      expect(remote.attachmentPayload!.name, startsWith(e2eeCiphertextPrefix));
      expect(
        remote.attachmentPayload!.dataBase64,
        startsWith(e2eeCiphertextPrefix),
      );
      expect(note.customAssigneeName, 'Camila');
      expect(attachment.name, 'comprobante.png');
      expect(attachment.dataBase64, 'aG9sYQ==');
      repository.dispose();
    },
  );

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

  test('decrypts list name changes received in real time', () async {
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
    final nameChanged = repository.realtimeEvents.firstWhere(
      (event) => event is ListNameChanged,
    );

    await repository.updateList('home-user-1', 'Me deben');
    final event = (await nameChanged) as ListNameChanged;

    expect(event.name, 'Me deben');
    expect(remote.rawList.name, startsWith(e2eeCiphertextPrefix));
    expect(remote.rawList.name, isNot(contains('Me deben')));

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

  test('persists offline note changes as ciphertext', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final store = InMemoryOfflineMutationStore();
    final remote = _FakeE2eeRemote();
    final repository = E2eeNotesRepository(
      repository: CachedNotesRepository(
        repository: remote,
        preferences: preferences,
        userIdProvider: () => 'user-1',
        mutationStore: store,
      ),
      userIdProvider: () => 'user-1',
      keyStore: E2eeKeyStore(storage: _MemorySecureStore()),
    );
    await repository.fetchLists();
    final note = (await repository.fetchNotes('home-user-1')).single;
    remote.isOffline = true;

    final local = await repository.updateNote(note.id, {
      'title': 'Idea privada sin conexión',
    });
    final stored = (await store.listForUser('user-1')).single;

    expect(local.title, 'Idea privada sin conexión');
    expect(stored.payload, contains(e2eeCiphertextPrefix));
    expect(stored.payload, isNot(contains('Idea privada sin conexión')));
    expect(stored.localNoteJson, isNot(contains('Idea privada sin conexión')));
    repository.dispose();
  });

  test('persists offline reactions without copying plaintext', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final store = InMemoryOfflineMutationStore();
    final remote = _FakeE2eeRemote();
    final repository = E2eeNotesRepository(
      repository: CachedNotesRepository(
        repository: remote,
        preferences: preferences,
        userIdProvider: () => 'user-1',
        mutationStore: store,
      ),
      userIdProvider: () => 'user-1',
      keyStore: E2eeKeyStore(storage: _MemorySecureStore()),
    );
    await repository.fetchLists();
    final note = (await repository.fetchNotes('home-user-1')).single;
    remote.isOffline = true;

    final local = await repository.setNoteReaction(note.id, '🚀', true);
    final stored = (await store.listForUser('user-1')).single;

    expect(local.title, 'Comprar pan');
    expect(local.reactions.single.userUids, ['user-1']);
    expect(stored.kind, StoredMutationKind.reaction);
    expect(stored.localNoteJson, contains(e2eeCiphertextPrefix));
    expect(stored.localNoteJson, isNot(contains('Comprar pan')));
    repository.dispose();
  });

  test('reuses a private in-memory index across search queries', () async {
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
    final first = await repository.searchNotes('comprar');
    final second = await repository.searchNotes('pan');

    expect(first.single.note.title, 'Comprar pan');
    expect(second.single.note.id, first.single.note.id);
    expect(remote.fetchNotesCalls, 2);
    await pumpEventQueue();
    final persisted = preferences.getString(CachedNotesRepository.storageKey);
    expect(persisted, isNot(contains('Comprar pan')));
    repository.dispose();
  });
}

class _FakeE2eeRemote extends Fake
    implements
        NotesRepository,
        E2eeNotesTransport,
        AggregateBoardAppearancesRepository,
        NoteAttachmentsRepository {
  final _events = StreamController<NotesRealtimeEvent>.broadcast();
  final date = DateTime.utc(2026, 8, 10);
  String registeredDeviceId = '';
  List<EncryptionRecipient> recipients = const [];
  final storedEnvelopes = <_StoredEnvelope>[];
  AggregateBoardAppearances aggregateBoardAppearances =
      const AggregateBoardAppearances();
  bool isOffline = false;
  int fetchNotesCalls = 0;
  String? initialCustomAssigneeName;
  NoteAttachment? attachmentPayload;

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
    customAssigneeName: initialCustomAssigneeName,
    attachment: attachmentPayload == null
        ? null
        : NoteAttachment(
            id: attachmentPayload!.id,
            name: attachmentPayload!.name,
            mimeType: attachmentPayload!.mimeType,
            sizeBytes: attachmentPayload!.sizeBytes,
          ),
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
  Future<NoteList> updateList(String listId, String name) async {
    final updatedAt = date.add(const Duration(minutes: 1));
    rawList = rawList.copyWith(name: name, updatedAt: updatedAt);
    _events.add(ListNameChanged(listId, name, updatedAt));
    return rawList;
  }

  @override
  Future<List<Note>> fetchNotes(String boardId) async {
    fetchNotesCalls++;
    return [rawNote];
  }

  @override
  Future<NoteAttachment> fetchAttachment(String noteId) async {
    final attachment = attachmentPayload;
    if (attachment == null) throw const NotesPersistenceFailure();
    return attachment;
  }

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
    if (isOffline) {
      throw DioException(
        requestOptions: RequestOptions(path: '/notes/$id'),
        type: DioExceptionType.connectionError,
      );
    }
    if (changes['attachment'] case final Map attachment) {
      attachmentPayload = NoteAttachment.fromJson(
        Map<String, dynamic>.from(attachment),
      );
    }
    rawNote = Note.fromJson({...rawNote.toJson(), ...changes});
    return rawNote;
  }

  @override
  Future<Note> setNoteReaction(String id, String emoji, bool active) async {
    if (isOffline) {
      throw DioException(
        requestOptions: RequestOptions(path: '/notes/$id/reactions'),
        type: DioExceptionType.connectionError,
      );
    }
    final reactions = List<NoteReaction>.of(rawNote.reactions);
    final index = reactions.indexWhere((reaction) => reaction.emoji == emoji);
    final users = index == -1 ? <String>{} : reactions[index].userUids.toSet();
    if (active) {
      users.add('user-1');
    } else {
      users.remove('user-1');
    }
    if (users.isEmpty) {
      if (index != -1) reactions.removeAt(index);
    } else {
      final reaction = NoteReaction(emoji: emoji, userUids: users.toList());
      if (index == -1) {
        reactions.add(reaction);
      } else {
        reactions[index] = reaction;
      }
    }
    rawNote = rawNote.copyWith(reactions: reactions, updatedAt: DateTime.now());
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
