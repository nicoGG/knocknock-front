import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:nocknock/features/notes/data/e2ee_crypto.dart';
import 'package:nocknock/features/notes/data/notes_repository.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';

typedef E2eeUserIdProvider = String? Function();

/// Encrypts every user-authored list/note field before it reaches the API or
/// the account cache. MongoDB and the backend only receive opaque ciphertext.
class E2eeNotesRepository
    implements NotesRepository, NotesCacheReader, GuestDataSyncTarget {
  E2eeNotesRepository({
    required NotesRepository repository,
    required E2eeUserIdProvider userIdProvider,
    E2eeKeyStore? keyStore,
    E2eeCipher? cipher,
  }) : _repository = repository,
       // ignore: prefer_initializing_formals
       _userIdProvider = userIdProvider,
       _keyStore = keyStore ?? E2eeKeyStore(),
       _cipher = cipher ?? E2eeCipher() {
    if (repository is! E2eeNotesTransport) {
      throw ArgumentError('El repositorio remoto no soporta cifrado E2EE');
    }
    _subscription = repository.realtimeEvents.listen(_onRealtimeEvent);
  }

  static const _listNameField = e2eeListNameField;
  static const _listBackgroundField = 'list:custom-background:v1';
  static const _noteTitleField = e2eeNoteTitleField;
  static const _noteContentField = 'note:content:v1';
  static const _noteDeltaField = 'note:content-delta:v1';
  static const _noteAuthorField = 'note:author-name:v1';
  static const _noteChecklistField = 'note:checklist-text:v1';

  final NotesRepository _repository;
  final E2eeUserIdProvider _userIdProvider;
  final E2eeKeyStore _keyStore;
  final E2eeCipher _cipher;
  final _events = StreamController<NotesRealtimeEvent>.broadcast();
  final _listKeys = <String, SecretKey>{};
  final _rawLists = <String, NoteList>{};
  final _noteBoards = <String, String>{};

  late final StreamSubscription<NotesRealtimeEvent> _subscription;
  E2eeDeviceIdentity? _identity;
  String? _identityUserId;
  Future<void>? _registration;

  E2eeNotesTransport get _transport => _repository as E2eeNotesTransport;

  @override
  Stream<NotesRealtimeEvent> get realtimeEvents => _events.stream;

  @override
  Future<void> connect(String boardId) => _repository.connect(boardId);

  @override
  void disconnect() => _repository.disconnect();

  @override
  Future<List<NoteList>> fetchLists() async {
    final identity = await _ensureIdentity(register: true);
    final rawLists = List<NoteList>.of(await _repository.fetchLists());
    for (var index = 0; index < rawLists.length; index++) {
      final raw = rawLists[index];
      final migrated = raw.encryption.version == 0 && raw.canInvite
          ? await _migrateLegacyList(raw, identity)
          : raw;
      rawLists[index] = migrated;
      _rawLists[migrated.id] = migrated;
      await _resolveListKey(migrated, identity);
    }
    for (final raw in rawLists.where((list) => list.canInvite)) {
      final key = _listKeys[raw.id];
      if (key != null && raw.encryption.version == 1) {
        await _shareMissingKeys(raw, key);
      }
    }
    return Future.wait(rawLists.map(_decryptList));
  }

  @override
  Future<NoteList> createList(String name) async {
    final identity = await _ensureIdentity(register: true);
    final key = await _cipher.newListKey();
    final publicKey = await identity.publicKeyEncoded();
    final envelope = ListKeyEnvelope(
      deviceId: identity.deviceId,
      envelope: await _cipher.wrapListKey(key, publicKey),
    );
    final raw = await _transport.createEncryptedList(
      encryptedName: await _cipher.encryptString(
        name.trim(),
        key,
        field: _listNameField,
      ),
      keyEnvelope: envelope,
    );
    await _rememberListKey(raw.id, key);
    _rawLists[raw.id] = raw;
    await _shareMissingKeys(raw, key);
    return _decryptList(raw);
  }

  @override
  Future<NoteList> updateList(String listId, String name) async {
    final key = await _requireListKey(listId);
    final raw = await _repository.updateList(
      listId,
      await _cipher.encryptString(name.trim(), key, field: _listNameField),
    );
    _rawLists[listId] = raw;
    return _decryptList(raw);
  }

  @override
  Future<List<NoteList>> reorderLists(List<String> orderedIds) async {
    final rawLists = await _repository.reorderLists(orderedIds);
    for (final list in rawLists) {
      _rawLists[list.id] = list;
    }
    return Future.wait(rawLists.map(_decryptList));
  }

  @override
  Future<void> deleteList(String listId) async {
    await _repository.deleteList(listId);
    final userId = _requireUserId();
    _rawLists.remove(listId);
    _listKeys.remove(listId);
    _noteBoards.removeWhere((_, boardId) => boardId == listId);
    await _keyStore.deleteListKey(userId, listId);
  }

  @override
  Future<NoteList> inviteCollaborator(String listId, String email) async {
    final raw = await _repository.inviteCollaborator(listId, email);
    _rawLists[listId] = raw;
    final key = await _requireListKey(listId);
    await _shareMissingKeys(raw, key);
    return _decryptList(raw);
  }

  @override
  Future<NoteList> removeCollaborator(
    String listId,
    String collaboratorUid,
  ) async {
    final raw = await _repository.removeCollaborator(listId, collaboratorUid);
    _rawLists[listId] = raw;
    return _decryptList(raw);
  }

  @override
  Future<NoteList> updateListAppearance(
    String listId,
    ListAppearance appearance,
  ) async {
    final key = await _requireListKey(listId);
    final customBackground = appearance.customBackgroundImage;
    final encryptedAppearance = ListAppearance(
      backgroundPreset: appearance.backgroundPreset,
      backgroundBlur: appearance.backgroundBlur,
      customBackgroundImage: customBackground == null
          ? null
          : await _cipher.encryptString(
              customBackground,
              key,
              field: _listBackgroundField,
            ),
    );
    final raw = await _repository.updateListAppearance(
      listId,
      encryptedAppearance,
    );
    _rawLists[listId] = raw;
    return _decryptList(raw);
  }

  @override
  Future<List<Note>> fetchNotes(String boardId) async {
    final key = await _listKeyOrNull(boardId);
    if (key == null) return const [];
    final rawNotes = await _repository.fetchNotes(boardId);
    for (final note in rawNotes) {
      _noteBoards[note.id] = note.boardId;
    }
    return Future.wait(rawNotes.map((note) => _decryptNote(note, key)));
  }

  @override
  Future<List<Note>> fetchPinnedNotes() async {
    if (_rawLists.isEmpty) await fetchLists();
    final rawNotes = await _repository.fetchPinnedNotes();
    final clearNotes = <Note>[];
    for (final raw in rawNotes) {
      _noteBoards[raw.id] = raw.boardId;
      final key = await _listKeyOrNull(raw.boardId);
      if (key != null) clearNotes.add(await _decryptNote(raw, key));
    }
    return clearNotes;
  }

  @override
  Future<List<Note>> fetchReminderNotes() async {
    if (_rawLists.isEmpty) await fetchLists();
    final rawNotes = await _repository.fetchReminderNotes();
    final clearNotes = <Note>[];
    for (final raw in rawNotes) {
      _noteBoards[raw.id] = raw.boardId;
      final key = await _listKeyOrNull(raw.boardId);
      if (key != null) clearNotes.add(await _decryptNote(raw, key));
    }
    return clearNotes;
  }

  @override
  Future<Note> createNote(String boardId, NoteDraft draft) async {
    final key = await _requireListKey(boardId);
    final raw = await _repository.createNote(
      boardId,
      await _encryptDraft(draft, key),
    );
    _noteBoards[raw.id] = raw.boardId;
    return _decryptNote(raw, key);
  }

  @override
  Future<Note> updateNote(String id, Map<String, dynamic> changes) async {
    final boardId = _noteBoards[id];
    if (boardId == null) throw const EncryptionKeyUnavailableFailure();
    final key = await _requireListKey(boardId);
    final encryptedChanges = await _encryptChanges(changes, key);
    final raw = await _repository.updateNote(id, encryptedChanges);
    _noteBoards[raw.id] = raw.boardId;
    return _decryptNote(raw, key);
  }

  @override
  Future<Note> setNoteReaction(String id, String emoji, bool active) async {
    final boardId = _noteBoards[id];
    if (boardId == null) throw const EncryptionKeyUnavailableFailure();
    final key = await _requireListKey(boardId);
    final raw = await _repository.setNoteReaction(id, emoji, active);
    _noteBoards[raw.id] = raw.boardId;
    return _decryptNote(raw, key);
  }

  @override
  Future<List<Note>> reorderNotes(
    String boardId,
    List<String> orderedIds,
  ) async {
    final key = await _requireListKey(boardId);
    final rawNotes = await _repository.reorderNotes(boardId, orderedIds);
    for (final note in rawNotes) {
      _noteBoards[note.id] = note.boardId;
    }
    return Future.wait(rawNotes.map((note) => _decryptNote(note, key)));
  }

  @override
  Future<void> deleteNote(String id) async {
    await _repository.deleteNote(id);
    _noteBoards.remove(id);
  }

  @override
  Future<NotesCacheSnapshot?> readCache() async {
    final repository = _repository;
    if (repository is! NotesCacheReader) return null;
    await _ensureIdentity(register: false);
    final raw = await (repository as NotesCacheReader).readCache();
    if (raw == null) return null;
    final clearLists = <NoteList>[];
    for (final list in raw.lists) {
      _rawLists[list.id] = list;
      await _resolveListKey(list, _identity!);
      clearLists.add(await _decryptList(list));
    }
    final clearNotes = <String, List<Note>>{};
    for (final entry in raw.notesByBoard.entries) {
      final key = await _listKeyOrNull(entry.key);
      if (key == null) continue;
      clearNotes[entry.key] = await Future.wait(
        entry.value.map((note) async {
          _noteBoards[note.id] = note.boardId;
          return _decryptNote(note, key);
        }),
      );
    }
    return NotesCacheSnapshot(lists: clearLists, notesByBoard: clearNotes);
  }

  @override
  Future<GuestDataSyncResult> syncGuestData(LocalNotesSnapshot snapshot) async {
    final target = _repository;
    if (target is! GuestDataSyncTarget) {
      throw const NotesPersistenceFailure();
    }
    final userId = _requireUserId();
    final identity = await _ensureIdentity(register: true);
    final serverLists = await fetchLists();
    final home = serverLists
        .where((list) => list.id == 'home-$userId')
        .firstOrNull;

    final keys = <String, SecretKey>{};
    final encryptedLists = <NoteList>[];
    for (final localList in snapshot.lists) {
      final isHome = localList.id == 'home';
      final key = isHome && home != null
          ? await _requireListKey(home.id)
          : await _cipher.newListKey();
      keys[localList.id] = key;
      final destinationId = isHome
          ? 'home-$userId'
          : await _importedListId(userId, localList.id);
      if (!isHome || home == null) {
        await _rememberListKey(destinationId, key);
      }
      final publicKey = await identity.publicKeyEncoded();
      final envelope = ListKeyEnvelope(
        deviceId: identity.deviceId,
        envelope: await _cipher.wrapListKey(key, publicKey),
      );
      final customBackground = localList.appearance.customBackgroundImage;
      encryptedLists.add(
        NoteList(
          id: localList.id,
          name: await _cipher.encryptString(
            localList.name,
            key,
            field: _listNameField,
          ),
          createdAt: localList.createdAt,
          updatedAt: localList.updatedAt,
          appearance: ListAppearance(
            backgroundPreset: localList.appearance.backgroundPreset,
            backgroundBlur: localList.appearance.backgroundBlur,
            customBackgroundImage: customBackground == null
                ? null
                : await _cipher.encryptString(
                    customBackground,
                    key,
                    field: _listBackgroundField,
                  ),
          ),
          encryption: ListEncryption(version: 1, keyEnvelopes: [envelope]),
        ),
      );
    }

    final encryptedNotes = <Note>[];
    for (final note in snapshot.notes) {
      final key = keys[note.boardId];
      if (key == null) throw const NotesPersistenceFailure();
      encryptedNotes.add(await _encryptNote(note, key));
    }
    return (target as GuestDataSyncTarget).syncGuestData(
      LocalNotesSnapshot(lists: encryptedLists, notes: encryptedNotes),
    );
  }

  Future<E2eeDeviceIdentity> _ensureIdentity({required bool register}) async {
    final userId = _requireUserId();
    if (_identityUserId != userId) {
      _identityUserId = userId;
      _identity = null;
      _registration = null;
      _listKeys.clear();
      _rawLists.clear();
      _noteBoards.clear();
    }
    final identity = _identity ??= await _keyStore.loadOrCreateIdentity(userId);
    if (register) {
      _registration ??= _transport.registerEncryptionDevice(
        deviceId: identity.deviceId,
        publicKey: await identity.publicKeyEncoded(),
      );
      try {
        await _registration;
      } on Object {
        _registration = null;
        rethrow;
      }
    }
    return identity;
  }

  Future<NoteList> _migrateLegacyList(
    NoteList raw,
    E2eeDeviceIdentity identity,
  ) async {
    final userId = _requireUserId();
    final key =
        await _keyStore.readListKey(userId, raw.id) ??
        await _cipher.newListKey();
    await _rememberListKey(raw.id, key);
    final notes = await _repository.fetchNotes(raw.id);
    for (final note in notes) {
      _noteBoards[note.id] = note.boardId;
      await _repository.updateNote(
        note.id,
        await _encryptedNoteChanges(note, key),
      );
    }
    final customBackground = raw.appearance.customBackgroundImage;
    final publicKey = await identity.publicKeyEncoded();
    final migrated = await _transport.enableListEncryption(
      listId: raw.id,
      encryptedName: await _encryptIfNeeded(
        raw.name,
        key,
        field: _listNameField,
      ),
      encryptedCustomBackgroundImage: customBackground == null
          ? null
          : await _encryptIfNeeded(
              customBackground,
              key,
              field: _listBackgroundField,
            ),
      keyEnvelope: ListKeyEnvelope(
        deviceId: identity.deviceId,
        envelope: await _cipher.wrapListKey(key, publicKey),
      ),
    );
    _rawLists[migrated.id] = migrated;
    return migrated;
  }

  Future<SecretKey?> _resolveListKey(
    NoteList raw,
    E2eeDeviceIdentity identity,
  ) async {
    final known = _listKeys[raw.id];
    if (known != null) return known;
    final userId = _requireUserId();
    final stored = await _keyStore.readListKey(userId, raw.id);
    if (stored != null) {
      if (raw.encryption.version == 0 || await _canDecryptList(raw, stored)) {
        _listKeys[raw.id] = stored;
        return stored;
      }
    }
    final envelope = raw.encryption.keyEnvelopes
        .where((entry) => entry.deviceId == identity.deviceId)
        .firstOrNull;
    if (envelope == null) return null;
    final key = await _cipher.unwrapListKey(
      envelope.envelope,
      identity.keyPair,
    );
    if (!await _canDecryptList(raw, key)) {
      throw const EncryptionKeyUnavailableFailure();
    }
    await _rememberListKey(raw.id, key);
    return key;
  }

  Future<bool> _canDecryptList(NoteList raw, SecretKey key) async {
    if (!E2eeCipher.isCiphertext(raw.name)) return false;
    try {
      await _cipher.decryptString(raw.name, key, field: _listNameField);
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> _shareMissingKeys(NoteList raw, SecretKey key) async {
    if (!raw.canInvite || raw.encryption.version != 1) return;
    final recipients = await _transport.fetchEncryptionRecipients(raw.id);
    for (final recipient in recipients.where((entry) => !entry.hasEnvelope)) {
      await _transport.storeListKeyEnvelope(
        listId: raw.id,
        recipientUid: recipient.userUid,
        deviceId: recipient.deviceId,
        envelope: await _cipher.wrapListKey(key, recipient.publicKey),
      );
    }
  }

  Future<NoteList> _decryptList(NoteList raw) async {
    final key = await _listKeyOrNull(raw.id);
    if (raw.encryption.version != 1 || key == null) {
      return raw.copyWith(
        name: raw.encryption.version == 0
            ? 'Lista pendiente de cifrado'
            : 'Lista cifrada pendiente de llave',
        appearance: ListAppearance(
          backgroundPreset: raw.appearance.backgroundPreset,
          backgroundBlur: raw.appearance.backgroundBlur,
        ),
      );
    }
    final customBackground = raw.appearance.customBackgroundImage;
    return raw.copyWith(
      name: await _cipher.decryptString(raw.name, key, field: _listNameField),
      appearance: ListAppearance(
        backgroundPreset: raw.appearance.backgroundPreset,
        backgroundBlur: raw.appearance.backgroundBlur,
        customBackgroundImage: customBackground == null
            ? null
            : await _cipher.decryptString(
                customBackground,
                key,
                field: _listBackgroundField,
              ),
      ),
    );
  }

  Future<NoteDraft> _encryptDraft(NoteDraft draft, SecretKey key) async =>
      NoteDraft(
        title: await _cipher.encryptString(
          draft.title,
          key,
          field: _noteTitleField,
        ),
        content: await _cipher.encryptString(
          draft.content,
          key,
          field: _noteContentField,
        ),
        contentDelta: draft.contentDelta == null
            ? null
            : await _cipher.encryptString(
                draft.contentDelta!,
                key,
                field: _noteDeltaField,
              ),
        color: draft.color,
        authorName: await _cipher.encryptString(
          draft.authorName,
          key,
          field: _noteAuthorField,
        ),
        assigneeUid: draft.assigneeUid,
        category: draft.category,
        checklist: await Future.wait(
          draft.checklist.map(
            (item) async => NoteChecklistItem(
              id: item.id,
              text: await _cipher.encryptString(
                item.text,
                key,
                field: _noteChecklistField,
              ),
              isCompleted: item.isCompleted,
              indent: item.indent,
            ),
          ),
        ),
        reminderAt: draft.reminderAt,
      );

  Future<Map<String, dynamic>> _encryptChanges(
    Map<String, dynamic> changes,
    SecretKey key,
  ) async {
    final encrypted = Map<String, dynamic>.of(changes);
    for (final entry in const {
      'title': _noteTitleField,
      'content': _noteContentField,
      'contentDelta': _noteDeltaField,
      'authorName': _noteAuthorField,
    }.entries) {
      final value = encrypted[entry.key];
      if (value is String) {
        encrypted[entry.key] = await _cipher.encryptString(
          value,
          key,
          field: entry.value,
        );
      }
    }
    final checklist = encrypted['checklist'];
    if (checklist is List) {
      encrypted['checklist'] = await Future.wait(
        checklist.map((raw) async {
          final item = Map<String, dynamic>.from(raw as Map);
          item['text'] = await _cipher.encryptString(
            item['text'] as String? ?? '',
            key,
            field: _noteChecklistField,
          );
          return item;
        }),
      );
    }
    return encrypted;
  }

  Future<Map<String, dynamic>> _encryptedNoteChanges(
    Note note,
    SecretKey key,
  ) async => {
    'title': await _encryptIfNeeded(note.title, key, field: _noteTitleField),
    'content': await _encryptIfNeeded(
      note.content,
      key,
      field: _noteContentField,
    ),
    'contentDelta': note.contentDelta == null
        ? null
        : await _encryptIfNeeded(
            note.contentDelta!,
            key,
            field: _noteDeltaField,
          ),
    'authorName': await _encryptIfNeeded(
      note.authorName,
      key,
      field: _noteAuthorField,
    ),
    'checklist': await Future.wait(
      note.checklist.map(
        (item) async => {
          ...item.toJson(),
          'text': await _encryptIfNeeded(
            item.text,
            key,
            field: _noteChecklistField,
          ),
        },
      ),
    ),
  };

  Future<Note> _encryptNote(Note note, SecretKey key) async {
    final changes = await _encryptedNoteChanges(note, key);
    return _copyNote(
      note,
      title: changes['title'] as String,
      content: changes['content'] as String,
      contentDelta: changes['contentDelta'] as String?,
      authorName: changes['authorName'] as String,
      checklist: (changes['checklist'] as List<dynamic>)
          .map(
            (item) => NoteChecklistItem.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
    );
  }

  Future<Note> _decryptNote(Note raw, SecretKey key) async {
    if (!E2eeCipher.isCiphertext(raw.title) ||
        !E2eeCipher.isCiphertext(raw.content) ||
        !E2eeCipher.isCiphertext(raw.authorName) ||
        raw.checklist.any((item) => !E2eeCipher.isCiphertext(item.text))) {
      throw const EncryptionKeyUnavailableFailure();
    }
    return _copyNote(
      raw,
      title: await _cipher.decryptString(
        raw.title,
        key,
        field: _noteTitleField,
      ),
      content: await _cipher.decryptString(
        raw.content,
        key,
        field: _noteContentField,
      ),
      contentDelta: raw.contentDelta == null
          ? null
          : await _cipher.decryptString(
              raw.contentDelta!,
              key,
              field: _noteDeltaField,
            ),
      authorName: await _cipher.decryptString(
        raw.authorName,
        key,
        field: _noteAuthorField,
      ),
      checklist: await Future.wait(
        raw.checklist.map(
          (item) async => item.copyWith(
            text: await _cipher.decryptString(
              item.text,
              key,
              field: _noteChecklistField,
            ),
          ),
        ),
      ),
    );
  }

  Note _copyNote(
    Note note, {
    required String title,
    required String content,
    required String? contentDelta,
    required String authorName,
    required List<NoteChecklistItem> checklist,
  }) => Note(
    id: note.id,
    boardId: note.boardId,
    title: title,
    content: content,
    contentDelta: contentDelta,
    color: note.color,
    authorName: authorName,
    assigneeUid: note.assigneeUid,
    isCompleted: note.isCompleted,
    isPinned: note.isPinned,
    sortOrder: note.sortOrder,
    category: note.category,
    checklist: checklist,
    reactions: note.reactions,
    positionX: note.positionX,
    positionY: note.positionY,
    reminderAt: note.reminderAt,
    createdAt: note.createdAt,
    updatedAt: note.updatedAt,
  );

  Future<String> _encryptIfNeeded(
    String value,
    SecretKey key, {
    required String field,
  }) => E2eeCipher.isCiphertext(value)
      ? Future.value(value)
      : _cipher.encryptString(value, key, field: field);

  Future<SecretKey?> _listKeyOrNull(String listId) async {
    final known = _listKeys[listId];
    if (known != null) return known;
    final raw = _rawLists[listId];
    if (raw == null) return null;
    final identity = await _ensureIdentity(register: false);
    return _resolveListKey(raw, identity);
  }

  Future<SecretKey> _requireListKey(String listId) async {
    final key = await _listKeyOrNull(listId);
    if (key == null) throw const EncryptionKeyUnavailableFailure();
    return key;
  }

  Future<void> _rememberListKey(String listId, SecretKey key) async {
    final userId = _requireUserId();
    _listKeys[listId] = key;
    await _keyStore.writeListKey(userId, listId, key);
  }

  String _requireUserId() {
    final userId = _userIdProvider();
    if (userId == null || userId.isEmpty) {
      throw const EncryptionKeyUnavailableFailure();
    }
    return userId;
  }

  Future<String> _importedListId(String userId, String localId) async {
    final digest = await Sha256().hash(utf8.encode('$userId\u0000$localId'));
    final hex = digest.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return 'guest-list-${hex.substring(0, 32)}';
  }

  void _onRealtimeEvent(NotesRealtimeEvent event) {
    unawaited(_handleRealtimeEvent(event));
  }

  Future<void> _handleRealtimeEvent(NotesRealtimeEvent event) async {
    try {
      switch (event) {
        case NoteChanged(:final note):
          _noteBoards[note.id] = note.boardId;
          final key = await _listKeyOrNull(note.boardId);
          if (key != null) {
            _events.add(NoteChanged(await _decryptNote(note, key)));
          }
        case NotesReordered(:final boardId, :final notes):
          final key = await _listKeyOrNull(boardId);
          if (key != null) {
            _events.add(
              NotesReordered(
                boardId,
                await Future.wait(notes.map((note) => _decryptNote(note, key))),
              ),
            );
          }
        case ListAppearanceChanged(:final listId, :final appearance):
          final key = await _listKeyOrNull(listId);
          if (key == null) return;
          final custom = appearance.customBackgroundImage;
          _events.add(
            ListAppearanceChanged(
              listId,
              ListAppearance(
                backgroundPreset: appearance.backgroundPreset,
                backgroundBlur: appearance.backgroundBlur,
                customBackgroundImage: custom == null
                    ? null
                    : await _cipher.decryptString(
                        custom,
                        key,
                        field: _listBackgroundField,
                      ),
              ),
            ),
          );
        case ListAccessRemoved(:final listId):
          final userId = _requireUserId();
          _rawLists.remove(listId);
          _listKeys.remove(listId);
          _noteBoards.removeWhere((_, boardId) => boardId == listId);
          await _keyStore.deleteListKey(userId, listId);
          _events.add(event);
        case NoteRemoved() ||
            RealtimeConnectionChanged() ||
            RealtimeConnectionAttemptStarted() ||
            NotesSourceChanged() ||
            GuestDataSyncStarted() ||
            GuestDataSyncCompleted() ||
            GuestDataSyncFailed():
          _events.add(event);
      }
    } on Object {
      // Invalid or unavailable ciphertext is never forwarded as plaintext.
    }
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    _repository.dispose();
    unawaited(_events.close());
  }
}
