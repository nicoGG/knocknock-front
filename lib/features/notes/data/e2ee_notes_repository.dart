import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:nocknock/features/notes/data/e2ee_account_recovery.dart';
import 'package:nocknock/features/notes/data/e2ee_crypto.dart';
import 'package:nocknock/features/notes/data/notes_repository.dart';
import 'package:nocknock/features/notes/data/note_search.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';

typedef E2eeUserIdProvider = String? Function();

/// Encrypts every user-authored list/note field before it reaches the API or
/// the account cache. MongoDB and the backend only receive opaque ciphertext.
class E2eeNotesRepository
    implements
        NotesRepository,
        NotesCacheReader,
        GuestDataSyncTarget,
        AggregateBoardAppearancesRepository,
        AssignedNotesRepository,
        OfflineSyncRepository,
        NotesSearchRepository,
        NoteAttachmentsRepository,
        TrashNotesRepository,
        PaginatedNotesRepository {
  E2eeNotesRepository({
    required NotesRepository repository,
    required E2eeUserIdProvider userIdProvider,
    E2eeKeyStore? keyStore,
    E2eeCipher? cipher,
    E2eeAccountRecoveryIdentityStore? accountRecoveryIdentityStore,
  }) : _repository = repository,
       // ignore: prefer_initializing_formals
       _userIdProvider = userIdProvider,
       _keyStore = keyStore ?? E2eeKeyStore(),
       _cipher = cipher ?? E2eeCipher(),
       // ignore: prefer_initializing_formals
       _accountRecoveryIdentityStore = accountRecoveryIdentityStore {
    if (repository is! E2eeNotesTransport) {
      throw ArgumentError('El repositorio remoto no soporta cifrado E2EE');
    }
    _subscription = repository.realtimeEvents.listen(_onRealtimeEvent);
  }

  static const _listNameField = e2eeListNameField;
  static const _listBackgroundField = 'list:custom-background:v1';
  static const _aggregateBoardBackgroundFieldPrefix =
      'account:aggregate-board-background:v1';
  static const _noteTitleField = e2eeNoteTitleField;
  static const _noteContentField = 'note:content:v1';
  static const _noteDeltaField = 'note:content-delta:v1';
  static const _noteAuthorField = 'note:author-name:v1';
  static const _noteChecklistField = 'note:checklist-text:v1';
  static const _noteCustomAssigneeField = 'note:custom-assignee:v1';
  static const _noteAttachmentNameField = 'note:attachment-name:v1';
  static const _noteAttachmentDataField = 'note:attachment-data:v1';

  final NotesRepository _repository;
  final E2eeUserIdProvider _userIdProvider;
  final E2eeKeyStore _keyStore;
  final E2eeCipher _cipher;
  final E2eeAccountRecoveryIdentityStore? _accountRecoveryIdentityStore;
  final _events = StreamController<NotesRealtimeEvent>.broadcast();
  final _listKeys = <String, SecretKey>{};
  final _rawLists = <String, NoteList>{};
  final _clearLists = <String, NoteList>{};
  final _noteBoards = <String, String>{};
  final _trashNoteIds = <String>{};
  final _searchIndex = PrivateNoteSearchIndex();
  final _fullyIndexedBoardIds = <String>{};

  late final StreamSubscription<NotesRealtimeEvent> _subscription;
  E2eeDeviceIdentity? _identity;
  E2eeDeviceIdentity? _accountRecoveryIdentity;
  String? _identityUserId;
  Future<void>? _registration;
  Future<void>? _accountRecoveryRegistration;
  Future<void>? _searchWarmup;

  E2eeNotesTransport get _transport => _repository as E2eeNotesTransport;

  AggregateBoardAppearancesRepository get _aggregateBoardRepository {
    final repository = _repository;
    if (repository is! AggregateBoardAppearancesRepository) {
      throw const NotesPersistenceFailure();
    }
    return repository as AggregateBoardAppearancesRepository;
  }

  OfflineSyncRepository get _offlineRepository {
    final repository = _repository;
    if (repository is! OfflineSyncRepository) {
      throw const NotesPersistenceFailure();
    }
    return repository as OfflineSyncRepository;
  }

  @override
  Stream<NotesRealtimeEvent> get realtimeEvents => _events.stream;

  @override
  Future<void> connect(String boardId) => _repository.connect(boardId);

  @override
  void disconnect() => _repository.disconnect();

  @override
  Future<List<NoteList>> fetchLists() async {
    final identity = await _ensureIdentity(register: true);
    await _ensureAccountRecoveryIdentityBestEffort(register: true);
    final rawLists = List<NoteList>.of(await _repository.fetchLists());
    final fetchedIds = rawLists.map((list) => list.id).toSet();
    final removedIds = _rawLists.keys
        .where((id) => !fetchedIds.contains(id))
        .toList();
    for (final id in removedIds) {
      _rawLists.remove(id);
      _clearLists.remove(id);
      _noteBoards.removeWhere((_, boardId) => boardId == id);
      _searchIndex.removeBoard(id);
      _fullyIndexedBoardIds.remove(id);
    }
    for (var index = 0; index < rawLists.length; index++) {
      final raw = rawLists[index];
      final migrated = raw.encryption.version == 0 && raw.canInvite
          ? await _migrateLegacyList(raw, identity)
          : raw;
      rawLists[index] = migrated;
      _rawLists[migrated.id] = migrated;
      await _resolveListKey(migrated, identity);
    }
    for (final raw in rawLists) {
      final key = _listKeys[raw.id];
      if (key != null && raw.encryption.version == 1) {
        await _shareMissingKeysBestEffort(raw, key);
      }
    }
    final clearLists = await Future.wait(rawLists.map(_decryptList));
    _clearLists
      ..clear()
      ..addEntries(clearLists.map((list) => MapEntry(list.id, list)));
    return clearLists;
  }

  @override
  Future<NoteList> createList(String name) async {
    final identity = await _ensureIdentity(register: true);
    await _ensureAccountRecoveryIdentityBestEffort(register: true);
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
    final clear = await _decryptList(raw);
    _clearLists[raw.id] = clear;
    return clear;
  }

  @override
  Future<NoteList> updateList(String listId, String name) async {
    final key = await _requireListKey(listId);
    final raw = await _repository.updateList(
      listId,
      await _cipher.encryptString(name.trim(), key, field: _listNameField),
    );
    _rawLists[listId] = raw;
    final clear = await _decryptList(raw);
    _clearLists[listId] = clear;
    return clear;
  }

  @override
  Future<List<NoteList>> reorderLists(List<String> orderedIds) async {
    final rawLists = await _repository.reorderLists(orderedIds);
    for (final list in rawLists) {
      _rawLists[list.id] = list;
    }
    final clearLists = await Future.wait(rawLists.map(_decryptList));
    for (final list in clearLists) {
      _clearLists[list.id] = list;
    }
    return clearLists;
  }

  @override
  Future<void> deleteList(String listId) async {
    await _repository.deleteList(listId);
    final userId = _requireUserId();
    _rawLists.remove(listId);
    _clearLists.remove(listId);
    _noteBoards.removeWhere((_, boardId) => boardId == listId);
    _searchIndex.removeBoard(listId);
    _fullyIndexedBoardIds.remove(listId);
    if (listId != 'home-$userId') {
      _listKeys.remove(listId);
      await _keyStore.deleteListKey(userId, listId);
    }
  }

  @override
  Future<NoteList> inviteCollaborator(String listId, String email) async {
    final raw = await _repository.inviteCollaborator(listId, email);
    _rawLists[listId] = raw;
    final key = await _requireListKey(listId);
    await _shareMissingKeys(raw, key);
    final clear = await _decryptList(raw);
    _clearLists[listId] = clear;
    return clear;
  }

  @override
  Future<NoteList> removeCollaborator(
    String listId,
    String collaboratorUid,
  ) async {
    final raw = await _repository.removeCollaborator(listId, collaboratorUid);
    _rawLists[listId] = raw;
    final clear = await _decryptList(raw);
    _clearLists[listId] = clear;
    return clear;
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
    final clear = await _decryptList(raw);
    _clearLists[listId] = clear;
    return clear;
  }

  @override
  Future<AggregateBoardAppearances> fetchAggregateBoardAppearances() async {
    final key = await _aggregateBoardAppearanceKey();
    final raw = await _aggregateBoardRepository
        .fetchAggregateBoardAppearances();
    return _decryptAggregateBoardAppearances(raw, key);
  }

  @override
  Future<AggregateBoardAppearances> updateAggregateBoardAppearance(
    AggregateBoardScope scope,
    ListAppearance appearance,
  ) async {
    final key = await _aggregateBoardAppearanceKey();
    final customBackground = appearance.customBackgroundImage;
    final encryptedAppearance = ListAppearance(
      backgroundPreset: appearance.backgroundPreset,
      backgroundBlur: appearance.backgroundBlur,
      customBackgroundImage: customBackground == null
          ? null
          : await _cipher.encryptString(
              customBackground,
              key,
              field: _aggregateBoardBackgroundField(scope),
            ),
    );
    final raw = await _aggregateBoardRepository.updateAggregateBoardAppearance(
      scope,
      encryptedAppearance,
    );
    return _decryptAggregateBoardAppearances(raw, key);
  }

  @override
  Future<List<Note>> fetchNotes(String boardId) async {
    final key = await _listKeyOrNull(boardId);
    if (key == null) return const [];
    final rawNotes = await _repository.fetchNotes(boardId);
    for (final note in rawNotes) {
      _noteBoards[note.id] = note.boardId;
    }
    final clearNotes = await Future.wait(
      rawNotes.map((note) => _decryptNote(note, key)),
    );
    for (final note in clearNotes) {
      _searchIndex.upsert(note);
    }
    _fullyIndexedBoardIds.add(boardId);
    return clearNotes;
  }

  @override
  Future<NotesPage> fetchNotesPage(
    String boardId, {
    String? cursor,
    int limit = 40,
  }) async {
    final key = await _listKeyOrNull(boardId);
    if (key == null) return const NotesPage(items: [], nextCursor: null);
    final repository = _repository;
    if (repository is! PaginatedNotesRepository) {
      if (cursor != null) return const NotesPage(items: [], nextCursor: null);
      return NotesPage(items: await fetchNotes(boardId), nextCursor: null);
    }
    final rawPage = await (repository as PaginatedNotesRepository)
        .fetchNotesPage(boardId, cursor: cursor, limit: limit);
    for (final note in rawPage.items) {
      _noteBoards[note.id] = note.boardId;
    }
    final clearNotes = await Future.wait(
      rawPage.items.map((note) => _decryptNote(note, key)),
    );
    for (final note in clearNotes) {
      _searchIndex.upsert(note);
    }
    if (!rawPage.hasMore) _fullyIndexedBoardIds.add(boardId);
    return NotesPage(items: clearNotes, nextCursor: rawPage.nextCursor);
  }

  @override
  Future<List<Note>> fetchAssignedNotes() async {
    final repository = _repository;
    if (repository is! AssignedNotesRepository) return const [];
    if (_rawLists.isEmpty) await fetchLists();
    final rawNotes = await (repository as AssignedNotesRepository)
        .fetchAssignedNotes();
    return _decryptAggregateNotes(rawNotes);
  }

  @override
  Future<List<Note>> fetchPinnedNotes() async {
    if (_rawLists.isEmpty) await fetchLists();
    final rawNotes = await _repository.fetchPinnedNotes();
    final clearNotes = <Note>[];
    for (final raw in rawNotes) {
      _noteBoards[raw.id] = raw.boardId;
      final key = await _listKeyOrNull(raw.boardId);
      if (key != null) {
        final note = await _decryptNote(raw, key);
        _searchIndex.upsert(note);
        clearNotes.add(note);
      }
    }
    return clearNotes;
  }

  Future<List<Note>> _decryptAggregateNotes(List<Note> rawNotes) async {
    final clearNotes = <Note>[];
    for (final raw in rawNotes) {
      _noteBoards[raw.id] = raw.boardId;
      final key = await _listKeyOrNull(raw.boardId);
      if (key != null) {
        final note = await _decryptNote(raw, key);
        _searchIndex.upsert(note);
        clearNotes.add(note);
      }
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
      if (key != null) {
        final note = await _decryptNote(raw, key);
        _searchIndex.upsert(note);
        clearNotes.add(note);
      }
    }
    return clearNotes;
  }

  @override
  Future<List<Note>> fetchTrash() async {
    final repository = _repository;
    if (repository is! TrashNotesRepository) return const [];
    if (_rawLists.isEmpty) await fetchLists();
    final rawNotes = await (repository as TrashNotesRepository).fetchTrash();
    final clearNotes = await _decryptAggregateNotes(rawNotes);
    _trashNoteIds
      ..clear()
      ..addAll(rawNotes.map((note) => note.id));
    return clearNotes;
  }

  @override
  Future<Note> restoreNote(String id) async {
    final repository = _repository;
    if (repository is! TrashNotesRepository) {
      throw const NotesPersistenceFailure();
    }
    final raw = await (repository as TrashNotesRepository).restoreNote(id);
    final key = await _requireListKey(raw.boardId);
    _noteBoards[raw.id] = raw.boardId;
    final note = await _decryptNote(raw, key);
    _trashNoteIds.remove(id);
    _searchIndex.upsert(note);
    return note;
  }

  @override
  Future<void> permanentlyDeleteNote(String id) async {
    final repository = _repository;
    if (repository is! TrashNotesRepository) {
      throw const NotesPersistenceFailure();
    }
    await (repository as TrashNotesRepository).permanentlyDeleteNote(id);
    _trashNoteIds.remove(id);
    _noteBoards.remove(id);
    _searchIndex.remove(id);
  }

  @override
  Future<int> emptyTrash() async {
    final repository = _repository;
    if (repository is! TrashNotesRepository) {
      throw const NotesPersistenceFailure();
    }
    final deletedCount = await (repository as TrashNotesRepository)
        .emptyTrash();
    for (final id in _trashNoteIds) {
      _noteBoards.remove(id);
      _searchIndex.remove(id);
    }
    _trashNoteIds.clear();
    return deletedCount;
  }

  @override
  Future<List<NoteSearchResult>> searchNotes(String query) async {
    if (_rawLists.isEmpty) await fetchLists();
    await _ensureSearchIndexWarm();
    return _searchIndex
        .search(query)
        .map(
          (note) => NoteSearchResult(
            note: note,
            list:
                _clearLists[note.boardId] ??
                _rawLists[note.boardId]!.copyWith(
                  name: 'Recuperando lista cifrada',
                  isEncryptionKeyPending: true,
                ),
          ),
        )
        .toList();
  }

  Future<void> _ensureSearchIndexWarm() async {
    final active = _searchWarmup;
    if (active != null) return active;
    final missingBoardIds = _rawLists.keys
        .where((id) => !_fullyIndexedBoardIds.contains(id))
        .toList();
    if (missingBoardIds.isEmpty) return;
    final warmup = Future.wait(
      missingBoardIds.map(_loadBoardIntoSearchIndex),
    ).then((_) {});
    _searchWarmup = warmup;
    try {
      await warmup;
    } finally {
      if (identical(_searchWarmup, warmup)) _searchWarmup = null;
    }
  }

  Future<void> _loadBoardIntoSearchIndex(String boardId) async {
    final key = await _listKeyOrNull(boardId);
    if (key == null) {
      _fullyIndexedBoardIds.add(boardId);
      return;
    }
    final rawNotes = await _repository.fetchNotes(boardId);
    for (final raw in rawNotes) {
      _noteBoards[raw.id] = raw.boardId;
      _searchIndex.upsert(await _decryptNote(raw, key));
    }
    _fullyIndexedBoardIds.add(boardId);
  }

  @override
  Future<OfflineSyncSummary> offlineSyncSummary() =>
      _offlineRepository.offlineSyncSummary();

  @override
  Future<void> syncPendingChanges() => _offlineRepository.syncPendingChanges();

  @override
  Future<List<NoteSyncConflict>> fetchNoteSyncConflicts() async {
    if (_rawLists.isEmpty && _repository is NotesCacheReader) {
      await readCache();
    }
    final rawConflicts = await _offlineRepository.fetchNoteSyncConflicts();
    final clear = <NoteSyncConflict>[];
    for (final conflict in rawConflicts) {
      final key = await _listKeyOrNull(conflict.remoteNote.boardId);
      if (key == null) continue;
      clear.add(
        NoteSyncConflict(
          mutationId: conflict.mutationId,
          kind: conflict.kind,
          localNote: await _decryptNote(conflict.localNote, key),
          remoteNote: await _decryptNote(conflict.remoteNote, key),
        ),
      );
    }
    return clear;
  }

  @override
  Future<void> resolveNoteSyncConflict(
    String mutationId,
    NoteConflictResolution resolution,
  ) => _offlineRepository.resolveNoteSyncConflict(mutationId, resolution);

  @override
  Future<Note> createNote(String boardId, NoteDraft draft) async {
    final key = await _requireListKey(boardId);
    final raw = await _repository.createNote(
      boardId,
      await _encryptDraft(draft, key),
    );
    _noteBoards[raw.id] = raw.boardId;
    final note = await _decryptNote(raw, key);
    _searchIndex.upsert(note);
    return note;
  }

  @override
  Future<NoteAttachment> fetchAttachment(
    String noteId,
    String attachmentId,
  ) async {
    final boardId = _noteBoards[noteId];
    if (boardId == null) throw const EncryptionKeyUnavailableFailure();
    final key = await _requireListKey(boardId);
    final repository = _repository;
    if (repository is! NoteAttachmentsRepository) {
      throw const NotesPersistenceFailure();
    }
    return _decryptAttachment(
      await (repository as NoteAttachmentsRepository).fetchAttachment(
        noteId,
        attachmentId,
      ),
      key,
    );
  }

  @override
  Future<Note> updateNote(String id, Map<String, dynamic> changes) async {
    final boardId = _noteBoards[id];
    if (boardId == null) throw const EncryptionKeyUnavailableFailure();
    final key = await _requireListKey(boardId);
    final encryptedChanges = await _encryptChanges(changes, key);
    final raw = await _repository.updateNote(id, encryptedChanges);
    _noteBoards[raw.id] = raw.boardId;
    final note = await _decryptNote(raw, key);
    _searchIndex.upsert(note);
    return note;
  }

  @override
  Future<Note> setNoteReaction(String id, String emoji, bool active) async {
    final boardId = _noteBoards[id];
    if (boardId == null) throw const EncryptionKeyUnavailableFailure();
    final key = await _requireListKey(boardId);
    final raw = await _repository.setNoteReaction(id, emoji, active);
    _noteBoards[raw.id] = raw.boardId;
    final note = await _decryptNote(raw, key);
    _searchIndex.upsert(note);
    return note;
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
    final clearNotes = await Future.wait(
      rawNotes.map((note) => _decryptNote(note, key)),
    );
    for (final note in clearNotes) {
      _searchIndex.upsert(note);
    }
    _fullyIndexedBoardIds.add(boardId);
    return clearNotes;
  }

  @override
  Future<void> deleteNote(
    String id, {
    int? expectedRevision,
    String? clientMutationId,
  }) async {
    await _repository.deleteNote(
      id,
      expectedRevision: expectedRevision,
      clientMutationId: clientMutationId,
    );
    _trashNoteIds.add(id);
    _noteBoards.remove(id);
    _searchIndex.remove(id);
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
    _clearLists
      ..clear()
      ..addEntries(clearLists.map((list) => MapEntry(list.id, list)));
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
      for (final note in clearNotes[entry.key]!) {
        _searchIndex.upsert(note);
      }
    }
    _fullyIndexedBoardIds.addAll(raw.fullyLoadedBoardIds);
    final aggregateBoardAppearances = raw.aggregateBoardAppearances;
    return NotesCacheSnapshot(
      lists: clearLists,
      notesByBoard: clearNotes,
      aggregateBoardAppearances: aggregateBoardAppearances == null
          ? null
          : await _decryptAggregateBoardAppearances(
              aggregateBoardAppearances,
              await _aggregateBoardAppearanceKey(),
            ),
      fullyLoadedBoardIds: raw.fullyLoadedBoardIds,
    );
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
      _accountRecoveryIdentity = null;
      _registration = null;
      _accountRecoveryRegistration = null;
      _listKeys.clear();
      _rawLists.clear();
      _clearLists.clear();
      _noteBoards.clear();
      _searchIndex.clear();
      _fullyIndexedBoardIds.clear();
      _searchWarmup = null;
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

  Future<E2eeDeviceIdentity?> _ensureAccountRecoveryIdentity({
    required bool register,
  }) async {
    final store = _accountRecoveryIdentityStore;
    if (store == null) return null;
    final identity = _accountRecoveryIdentity ??= await store
        .loadOrCreateIdentity(_requireUserId());
    if (identity == null) return null;
    if (register) {
      _accountRecoveryRegistration ??= _transport.registerEncryptionDevice(
        deviceId: identity.deviceId,
        publicKey: await identity.publicKeyEncoded(),
      );
      try {
        await _accountRecoveryRegistration;
      } on Object {
        _accountRecoveryRegistration = null;
        rethrow;
      }
    }
    return identity;
  }

  Future<E2eeDeviceIdentity?> _ensureAccountRecoveryIdentityBestEffort({
    required bool register,
  }) async {
    try {
      return await _ensureAccountRecoveryIdentity(register: register);
    } on Object {
      // A temporary Drive failure must not hide lists that this device can
      // already decrypt. The next refresh retries account recovery setup.
      return null;
    }
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
      var noteToEncrypt = note;
      if (note.photoAttachments.any((entry) => entry.dataBase64 == null)) {
        final repository = _repository;
        if (repository is! NoteAttachmentsRepository) {
          throw const NotesPersistenceFailure();
        }
        final fullAttachments = await Future.wait(
          note.photoAttachments.map(
            (attachment) => attachment.dataBase64 != null
                ? Future.value(attachment)
                : (repository as NoteAttachmentsRepository).fetchAttachment(
                    note.id,
                    attachment.id,
                  ),
          ),
        );
        noteToEncrypt = _copyNote(
          note,
          title: note.title,
          content: note.content,
          contentDelta: note.contentDelta,
          authorName: note.authorName,
          customAssigneeName: note.customAssigneeName,
          attachments: fullAttachments,
          checklist: note.checklist,
        );
      }
      await _repository.updateNote(
        note.id,
        await _encryptedNoteChanges(noteToEncrypt, key),
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
    if (envelope != null) {
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

    final recoveryIdentity =
        _accountRecoveryIdentity ??
        await _ensureAccountRecoveryIdentityBestEffort(register: true);
    if (recoveryIdentity == null) return null;
    final recoveryEnvelope = raw.encryption.keyEnvelopes
        .where((entry) => entry.deviceId == recoveryIdentity.deviceId)
        .firstOrNull;
    if (recoveryEnvelope == null) return null;
    final recoveredKey = await _cipher.unwrapListKey(
      recoveryEnvelope.envelope,
      recoveryIdentity.keyPair,
    );
    if (!await _canDecryptList(raw, recoveredKey)) {
      throw const EncryptionKeyUnavailableFailure();
    }
    await _rememberListKey(raw.id, recoveredKey);
    return recoveredKey;
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
    if (raw.encryption.version != 1) return;
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

  Future<void> _shareMissingKeysBestEffort(NoteList raw, SecretKey key) async {
    try {
      await _shareMissingKeys(raw, key);
    } on Object {
      // Key propagation must not hide otherwise readable lists. This also keeps
      // the new client compatible while the member-sharing backend rolls out.
    }
  }

  Future<NoteList> _decryptList(NoteList raw) async {
    final key = await _listKeyOrNull(raw.id);
    if (raw.encryption.version != 1 || key == null) {
      return raw.copyWith(
        name: raw.encryption.version == 0
            ? 'Lista pendiente de cifrado'
            : 'Recuperando lista cifrada',
        appearance: ListAppearance(
          backgroundPreset: raw.appearance.backgroundPreset,
          backgroundBlur: raw.appearance.backgroundBlur,
        ),
        isEncryptionKeyPending: raw.encryption.version == 1,
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
      isEncryptionKeyPending: false,
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
        customAssigneeName: draft.customAssigneeName == null
            ? null
            : await _cipher.encryptString(
                draft.customAssigneeName!,
                key,
                field: _noteCustomAssigneeField,
              ),
        attachments: await Future.wait(
          draft.photoAttachments.map(
            (attachment) => _encryptAttachment(attachment, key),
          ),
        ),
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
        reminderRecurrence: draft.reminderRecurrence,
        clientNoteId: draft.clientNoteId,
        clientMutationId: draft.clientMutationId,
        isCompleted: draft.isCompleted,
        isPinned: draft.isPinned,
        sortOrder: draft.sortOrder,
        positionX: draft.positionX,
        positionY: draft.positionY,
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
      'customAssigneeName': _noteCustomAssigneeField,
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
    final attachment = encrypted['attachment'];
    if (attachment is Map) {
      encrypted['attachment'] = (await _encryptAttachment(
        NoteAttachment.fromJson(Map<String, dynamic>.from(attachment)),
        key,
      )).toJson();
    }
    final attachments = encrypted['attachments'];
    if (attachments is List) {
      encrypted['attachments'] = await Future.wait(
        attachments.map(
          (raw) => _encryptAttachment(
            NoteAttachment.fromJson(Map<String, dynamic>.from(raw as Map)),
            key,
          ).then((attachment) => attachment.toJson()),
        ),
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
    if (note.customAssigneeName != null)
      'customAssigneeName': await _encryptIfNeeded(
        note.customAssigneeName!,
        key,
        field: _noteCustomAssigneeField,
      ),
    'attachments': await Future.wait(
      note.photoAttachments.map(
        (attachment) =>
            _encryptAttachment(attachment, key).then((item) => item.toJson()),
      ),
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
      customAssigneeName: changes['customAssigneeName'] as String?,
      attachments: (changes['attachments'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                NoteAttachment.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
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
        raw.checklist.any((item) => !E2eeCipher.isCiphertext(item.text)) ||
        (raw.customAssigneeName != null &&
            !E2eeCipher.isCiphertext(raw.customAssigneeName!)) ||
        raw.photoAttachments.any(
          (attachment) =>
              !E2eeCipher.isCiphertext(attachment.name) ||
              (attachment.dataBase64 != null &&
                  !E2eeCipher.isCiphertext(attachment.dataBase64!)),
        )) {
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
      customAssigneeName: raw.customAssigneeName == null
          ? null
          : await _cipher.decryptString(
              raw.customAssigneeName!,
              key,
              field: _noteCustomAssigneeField,
            ),
      attachments: await Future.wait(
        raw.photoAttachments.map(
          (attachment) => _decryptAttachment(attachment, key),
        ),
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
    required String? customAssigneeName,
    required List<NoteAttachment> attachments,
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
    customAssigneeName: customAssigneeName,
    attachments: attachments,
    isCompleted: note.isCompleted,
    isPinned: note.isPinned,
    sortOrder: note.sortOrder,
    category: note.category,
    checklist: checklist,
    reactions: note.reactions,
    positionX: note.positionX,
    positionY: note.positionY,
    reminderAt: note.reminderAt,
    reminderRecurrence: note.reminderRecurrence,
    revision: note.revision,
    deletedAt: note.deletedAt,
    createdAt: note.createdAt,
    updatedAt: note.updatedAt,
  );

  Future<NoteAttachment> _encryptAttachment(
    NoteAttachment attachment,
    SecretKey key,
  ) async => NoteAttachment(
    id: attachment.id,
    name: await _encryptIfNeeded(
      attachment.name,
      key,
      field: _noteAttachmentNameField,
    ),
    mimeType: attachment.mimeType,
    sizeBytes: attachment.sizeBytes,
    dataBase64: attachment.dataBase64 == null
        ? null
        : await _encryptIfNeeded(
            attachment.dataBase64!,
            key,
            field: _noteAttachmentDataField,
          ),
  );

  Future<NoteAttachment> _decryptAttachment(
    NoteAttachment attachment,
    SecretKey key,
  ) async {
    if (!E2eeCipher.isCiphertext(attachment.name) ||
        (attachment.dataBase64 != null &&
            !E2eeCipher.isCiphertext(attachment.dataBase64!))) {
      throw const EncryptionKeyUnavailableFailure();
    }
    return NoteAttachment(
      id: attachment.id,
      name: await _cipher.decryptString(
        attachment.name,
        key,
        field: _noteAttachmentNameField,
      ),
      mimeType: attachment.mimeType,
      sizeBytes: attachment.sizeBytes,
      dataBase64: attachment.dataBase64 == null
          ? null
          : await _cipher.decryptString(
              attachment.dataBase64!,
              key,
              field: _noteAttachmentDataField,
            ),
    );
  }

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
            final clear = await _decryptNote(note, key);
            _searchIndex.upsert(clear);
            _events.add(NoteChanged(clear));
          }
        case NotesReordered(:final boardId, :final notes):
          final key = await _listKeyOrNull(boardId);
          if (key != null) {
            final clearNotes = await Future.wait(
              notes.map((note) => _decryptNote(note, key)),
            );
            for (final note in clearNotes) {
              _searchIndex.upsert(note);
            }
            _fullyIndexedBoardIds.add(boardId);
            _events.add(NotesReordered(boardId, clearNotes));
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
        case ListNameChanged(:final listId, :final name, :final updatedAt):
          final key = await _listKeyOrNull(listId);
          if (key == null) return;
          final clearName = await _cipher.decryptString(
            name,
            key,
            field: _listNameField,
          );
          final rawList = _rawLists[listId];
          if (rawList != null) {
            _rawLists[listId] = rawList.copyWith(
              name: name,
              updatedAt: updatedAt,
            );
          }
          final clearList = _clearLists[listId];
          if (clearList != null) {
            _clearLists[listId] = clearList.copyWith(
              name: clearName,
              updatedAt: updatedAt,
            );
          }
          _events.add(ListNameChanged(listId, clearName, updatedAt));
        case AggregateBoardAppearanceChanged(:final scope, :final appearance):
          final key = await _aggregateBoardAppearanceKey();
          _events.add(
            AggregateBoardAppearanceChanged(
              scope,
              await _decryptAggregateBoardAppearance(scope, appearance, key),
            ),
          );
        case ListAccessRemoved(:final listId):
          final userId = _requireUserId();
          _rawLists.remove(listId);
          _clearLists.remove(listId);
          _listKeys.remove(listId);
          _noteBoards.removeWhere((_, boardId) => boardId == listId);
          _searchIndex.removeBoard(listId);
          _fullyIndexedBoardIds.remove(listId);
          await _keyStore.deleteListKey(userId, listId);
          _events.add(event);
        case ListKeyShareRequested(:final listId):
          final raw = _rawLists[listId];
          if (raw == null) return;
          final key = await _listKeyOrNull(listId);
          if (key != null) await _shareMissingKeys(raw, key);
        case ListKeyEnvelopeUpdated():
          _events.add(event);
        case NoteRemoved(:final id):
          _noteBoards.remove(id);
          _searchIndex.remove(id);
          _events.add(event);
        case RealtimeConnectionChanged() ||
            RealtimeConnectionAttemptStarted() ||
            NotesSourceChanged() ||
            GuestDataSyncStarted() ||
            GuestDataSyncCompleted() ||
            GuestDataSyncFailed() ||
            OfflineSyncStateChanged() ||
            OfflineSyncOperationDiscarded():
          _events.add(event);
      }
    } on Object {
      // Invalid or unavailable ciphertext is never forwarded as plaintext.
    }
  }

  Future<SecretKey> _aggregateBoardAppearanceKey() async {
    final userId = _requireUserId();
    final homeListId = 'home-$userId';
    if (!_rawLists.containsKey(homeListId)) await fetchLists();
    return _requireListKey(homeListId);
  }

  String _aggregateBoardBackgroundField(AggregateBoardScope scope) =>
      '$_aggregateBoardBackgroundFieldPrefix:${scope.name}';

  Future<AggregateBoardAppearances> _decryptAggregateBoardAppearances(
    AggregateBoardAppearances appearances,
    SecretKey key,
  ) async => AggregateBoardAppearances(
    assignedToMe: await _decryptAggregateBoardAppearance(
      AggregateBoardScope.assignedToMe,
      appearances.assignedToMe,
      key,
    ),
    pinned: await _decryptAggregateBoardAppearance(
      AggregateBoardScope.pinned,
      appearances.pinned,
      key,
    ),
    withReminder: await _decryptAggregateBoardAppearance(
      AggregateBoardScope.withReminder,
      appearances.withReminder,
      key,
    ),
  );

  Future<ListAppearance> _decryptAggregateBoardAppearance(
    AggregateBoardScope scope,
    ListAppearance appearance,
    SecretKey key,
  ) async {
    final customBackground = appearance.customBackgroundImage;
    return ListAppearance(
      backgroundPreset: appearance.backgroundPreset,
      backgroundBlur: appearance.backgroundBlur,
      customBackgroundImage:
          customBackground == null || !E2eeCipher.isCiphertext(customBackground)
          ? customBackground
          : await _cipher.decryptString(
              customBackground,
              key,
              field: _aggregateBoardBackgroundField(scope),
            ),
    );
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    _repository.dispose();
    unawaited(_events.close());
  }
}
