import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:nocknock/features/notes/data/notes_repository.dart';
import 'package:nocknock/features/notes/data/offline_mutation_store.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

typedef NotesCacheUserIdProvider = String? Function();

/// Adds an account-scoped, best-effort device cache to a remote repository.
///
/// Network reads still return authoritative data. [readCache] is used by the
/// presentation layer to paint the last successful snapshot immediately while
/// those reads revalidate it in the background.
class CachedNotesRepository
    implements
        NotesRepository,
        NotesCacheReader,
        GuestDataSyncTarget,
        E2eeNotesTransport,
        AggregateBoardAppearancesRepository,
        OfflineSyncRepository,
        NoteAttachmentsRepository,
        PaginatedNotesRepository {
  factory CachedNotesRepository({
    required NotesRepository repository,
    required SharedPreferences preferences,
    required NotesCacheUserIdProvider userIdProvider,
    OfflineMutationStore? mutationStore,
  }) => CachedNotesRepository._(
    repository,
    preferences,
    userIdProvider,
    mutationStore ?? InMemoryOfflineMutationStore(),
  );

  CachedNotesRepository._(
    this._repository,
    this._preferences,
    this._userIdProvider,
    this._mutationStore,
  ) {
    _realtimeSubscription = _repository.realtimeEvents.listen(_onRealtimeEvent);
  }

  static const storageKey = 'nocknock.account_notes_cache.v1';

  final NotesRepository _repository;
  final SharedPreferences _preferences;
  final NotesCacheUserIdProvider _userIdProvider;
  final OfflineMutationStore _mutationStore;
  final _events = StreamController<NotesRealtimeEvent>.broadcast();

  late final StreamSubscription<NotesRealtimeEvent> _realtimeSubscription;
  Future<void> _writeQueue = Future.value();
  String? _loadedUserId;
  _AccountNotesCache? _cache;
  bool _isSyncing = false;

  @override
  Stream<NotesRealtimeEvent> get realtimeEvents => _events.stream;

  @override
  Future<NotesCacheSnapshot?> readCache() async {
    final cache = _cacheFor(_userIdProvider());
    if (cache == null || cache.lists.isEmpty) return null;
    return NotesCacheSnapshot(
      lists: List.unmodifiable(cache.lists),
      notesByBoard: Map<String, List<Note>>.unmodifiable({
        for (final entry in cache.notesByBoard.entries)
          entry.key: List<Note>.unmodifiable(entry.value),
      }),
      aggregateBoardAppearances: cache.aggregateBoardAppearances,
      fullyLoadedBoardIds: Set.unmodifiable(cache.fullyLoadedBoardIds),
    );
  }

  @override
  Future<void> connect(String boardId) async {
    await _repository.connect(boardId);
    unawaited(syncPendingChanges());
  }

  @override
  void disconnect() => _repository.disconnect();

  @override
  Future<List<NoteList>> fetchLists() async {
    final userId = _userIdProvider();
    final lists = await _repository.fetchLists();
    unawaited(
      _updateCache(userId, (cache) {
        cache.lists = List.of(lists);
        final validIds = lists.map((list) => list.id).toSet();
        cache.notesByBoard.removeWhere((id, _) => !validIds.contains(id));
        cache.fullyLoadedBoardIds.removeWhere((id) => !validIds.contains(id));
        cache.pinnedNotes?.removeWhere(
          (note) => !validIds.contains(note.boardId),
        );
        cache.reminderNotes?.removeWhere(
          (note) => !validIds.contains(note.boardId),
        );
      }),
    );
    unawaited(syncPendingChanges());
    return lists;
  }

  @override
  Future<NoteList> createList(String name) async {
    final userId = _userIdProvider();
    final list = await _repository.createList(name);
    unawaited(
      _updateCache(userId, (cache) {
        if (cache.lists.isNotEmpty) cache.lists.add(list);
      }),
    );
    return list;
  }

  E2eeNotesTransport get _e2eeTransport {
    final repository = _repository;
    if (repository is! E2eeNotesTransport) {
      throw const EncryptionKeyUnavailableFailure();
    }
    return repository as E2eeNotesTransport;
  }

  AggregateBoardAppearancesRepository get _aggregateBoardRepository {
    final repository = _repository;
    if (repository is! AggregateBoardAppearancesRepository) {
      throw const NotesPersistenceFailure();
    }
    return repository as AggregateBoardAppearancesRepository;
  }

  @override
  Future<void> registerEncryptionDevice({
    required String deviceId,
    required String publicKey,
  }) => _e2eeTransport.registerEncryptionDevice(
    deviceId: deviceId,
    publicKey: publicKey,
  );

  @override
  Future<NoteList> createEncryptedList({
    required String encryptedName,
    required ListKeyEnvelope keyEnvelope,
  }) async {
    final userId = _userIdProvider();
    final list = await _e2eeTransport.createEncryptedList(
      encryptedName: encryptedName,
      keyEnvelope: keyEnvelope,
    );
    unawaited(
      _updateCache(userId, (cache) {
        if (cache.lists.isNotEmpty) cache.lists.add(list);
      }),
    );
    return list;
  }

  @override
  Future<NoteList> enableListEncryption({
    required String listId,
    required String encryptedName,
    required String? encryptedCustomBackgroundImage,
    required ListKeyEnvelope keyEnvelope,
  }) async {
    final userId = _userIdProvider();
    final list = await _e2eeTransport.enableListEncryption(
      listId: listId,
      encryptedName: encryptedName,
      encryptedCustomBackgroundImage: encryptedCustomBackgroundImage,
      keyEnvelope: keyEnvelope,
    );
    unawaited(_updateCache(userId, (cache) => _replaceList(cache, list)));
    return list;
  }

  @override
  Future<List<EncryptionRecipient>> fetchEncryptionRecipients(String listId) =>
      _e2eeTransport.fetchEncryptionRecipients(listId);

  @override
  Future<void> storeListKeyEnvelope({
    required String listId,
    required String recipientUid,
    required String deviceId,
    required String envelope,
  }) => _e2eeTransport.storeListKeyEnvelope(
    listId: listId,
    recipientUid: recipientUid,
    deviceId: deviceId,
    envelope: envelope,
  );

  @override
  Future<NoteList> updateList(String listId, String name) async {
    final userId = _userIdProvider();
    final list = await _repository.updateList(listId, name);
    unawaited(_updateCache(userId, (cache) => _replaceList(cache, list)));
    return list;
  }

  @override
  Future<List<NoteList>> reorderLists(List<String> orderedIds) async {
    final userId = _userIdProvider();
    final lists = await _repository.reorderLists(orderedIds);
    unawaited(
      _updateCache(userId, (cache) {
        cache.lists = List.of(lists);
      }),
    );
    return lists;
  }

  @override
  Future<void> deleteList(String listId) async {
    final userId = _userIdProvider();
    await _repository.deleteList(listId);
    unawaited(_updateCache(userId, (cache) => _removeList(cache, listId)));
  }

  @override
  Future<NoteList> inviteCollaborator(String listId, String email) async {
    final userId = _userIdProvider();
    final list = await _repository.inviteCollaborator(listId, email);
    unawaited(_updateCache(userId, (cache) => _replaceList(cache, list)));
    return list;
  }

  @override
  Future<NoteList> removeCollaborator(
    String listId,
    String collaboratorUid,
  ) async {
    final userId = _userIdProvider();
    final list = await _repository.removeCollaborator(listId, collaboratorUid);
    unawaited(_updateCache(userId, (cache) => _replaceList(cache, list)));
    return list;
  }

  @override
  Future<NoteList> updateListAppearance(
    String listId,
    ListAppearance appearance,
  ) async {
    final userId = _userIdProvider();
    final list = await _repository.updateListAppearance(listId, appearance);
    unawaited(_updateCache(userId, (cache) => _replaceList(cache, list)));
    return list;
  }

  @override
  Future<AggregateBoardAppearances> fetchAggregateBoardAppearances() async {
    final userId = _userIdProvider();
    final appearances = await _aggregateBoardRepository
        .fetchAggregateBoardAppearances();
    unawaited(
      _updateCache(
        userId,
        (cache) => cache.aggregateBoardAppearances = appearances,
      ),
    );
    return appearances;
  }

  @override
  Future<AggregateBoardAppearances> updateAggregateBoardAppearance(
    AggregateBoardScope scope,
    ListAppearance appearance,
  ) async {
    final userId = _userIdProvider();
    final appearances = await _aggregateBoardRepository
        .updateAggregateBoardAppearance(scope, appearance);
    unawaited(
      _updateCache(
        userId,
        (cache) => cache.aggregateBoardAppearances = appearances,
      ),
    );
    return appearances;
  }

  @override
  Future<List<Note>> fetchNotes(String boardId) async {
    final userId = _userIdProvider();
    late final List<Note> fetchedNotes;
    try {
      fetchedNotes = await _repository.fetchNotes(boardId);
    } catch (error) {
      final cached = _cacheFor(userId)?.notesByBoard[boardId];
      if (!_isRetryable(error) || cached == null) rethrow;
      return List<Note>.unmodifiable(cached);
    }
    final cachedById = {
      for (final note
          in _cacheFor(userId)?.notesByBoard[boardId] ?? const <Note>[])
        note.id: note,
    };
    final notes = fetchedNotes
        .map((note) => _preserveAttachmentData(note, cachedById[note.id]))
        .toList();
    await _updateCache(userId, (cache) {
      cache.notesByBoard[boardId] = _sortedNotes(notes);
      cache.fullyLoadedBoardIds.add(boardId);
      _replaceKnownPinnedNotes(cache, notes);
      _replaceKnownReminderNotes(cache, notes);
    });
    return notes;
  }

  @override
  Future<NotesPage> fetchNotesPage(
    String boardId, {
    String? cursor,
    int limit = 40,
  }) async {
    final repository = _repository;
    if (repository is! PaginatedNotesRepository) {
      if (cursor != null) return const NotesPage(items: [], nextCursor: null);
      return NotesPage(items: await fetchNotes(boardId), nextCursor: null);
    }

    final userId = _userIdProvider();
    late final NotesPage remotePage;
    try {
      remotePage = await (repository as PaginatedNotesRepository)
          .fetchNotesPage(boardId, cursor: cursor, limit: limit);
    } catch (error) {
      final cached = _cacheFor(userId)?.notesByBoard[boardId];
      if (cursor != null || !_isRetryable(error) || cached == null) rethrow;
      return NotesPage(
        items: List<Note>.unmodifiable(cached),
        nextCursor: null,
      );
    }

    final cachedById = {
      for (final note
          in _cacheFor(userId)?.notesByBoard[boardId] ?? const <Note>[])
        note.id: note,
    };
    final page = NotesPage(
      items: remotePage.items
          .map((note) => _preserveAttachmentData(note, cachedById[note.id]))
          .toList(),
      nextCursor: remotePage.nextCursor,
    );

    await _updateCache(userId, (cache) {
      if (cursor == null && !page.hasMore) {
        cache.notesByBoard[boardId] = _sortedNotes(page.items);
      } else {
        final merged = {
          for (final note in cache.notesByBoard[boardId] ?? const <Note>[])
            note.id: note,
          for (final note in page.items) note.id: note,
        };
        cache.notesByBoard[boardId] = _sortedNotes(merged.values);
      }
      if (page.hasMore) {
        cache.fullyLoadedBoardIds.remove(boardId);
      } else {
        cache.fullyLoadedBoardIds.add(boardId);
      }
      _replaceKnownPinnedNotes(cache, page.items);
      _replaceKnownReminderNotes(cache, page.items);
    });
    return page;
  }

  @override
  Future<List<Note>> fetchPinnedNotes() async {
    final userId = _userIdProvider();
    final notes = await _repository.fetchPinnedNotes();
    unawaited(
      _updateCache(userId, (cache) {
        cache.pinnedNotes = _sortedPinnedNotes(notes);
      }),
    );
    return notes;
  }

  @override
  Future<List<Note>> fetchReminderNotes() async {
    final userId = _userIdProvider();
    final notes = await _repository.fetchReminderNotes();
    unawaited(
      _updateCache(userId, (cache) {
        cache.reminderNotes = _sortedReminderNotes(notes);
      }),
    );
    return notes;
  }

  @override
  Future<Note> createNote(String boardId, NoteDraft draft) async {
    final userId = _userIdProvider();
    if (userId == null || userId.isEmpty) {
      return _repository.createNote(boardId, draft);
    }
    final operationId = draft.clientMutationId ?? const Uuid().v4();
    final noteId = draft.clientNoteId ?? const Uuid().v4();
    final synchronizedDraft = draft.withSyncContext(
      clientNoteId: noteId,
      clientMutationId: operationId,
    );
    try {
      final remote = await _repository.createNote(boardId, synchronizedDraft);
      final note = _withAttachmentData(
        remote,
        synchronizedDraft.photoAttachments,
      );
      await _updateCache(userId, (cache) => _upsertNote(cache, note));
      return note;
    } catch (error) {
      if (!_isRetryable(error)) rethrow;
      final now = DateTime.now();
      final provisional = Note(
        id: noteId,
        boardId: boardId,
        title: synchronizedDraft.title,
        content: synchronizedDraft.content,
        contentDelta: synchronizedDraft.contentDelta,
        color: synchronizedDraft.color,
        authorName: synchronizedDraft.authorName,
        assigneeUid: synchronizedDraft.assigneeUid,
        customAssigneeName: synchronizedDraft.customAssigneeName,
        attachments: synchronizedDraft.photoAttachments,
        category: synchronizedDraft.category,
        checklist: synchronizedDraft.checklist,
        isCompleted: synchronizedDraft.isCompleted,
        isPinned: synchronizedDraft.isPinned,
        sortOrder: synchronizedDraft.sortOrder ?? -now.microsecondsSinceEpoch,
        positionX: synchronizedDraft.positionX,
        positionY: synchronizedDraft.positionY,
        reminderAt: synchronizedDraft.reminderAt,
        createdAt: now,
        updatedAt: now,
      );
      await _mutationStore.put(
        StoredOfflineMutation(
          id: operationId,
          userId: userId,
          entityId: noteId,
          boardId: boardId,
          kind: StoredMutationKind.create,
          payload: jsonEncode(synchronizedDraft.toJson()),
          baseRevision: 0,
          createdAt: now,
          localNoteJson: jsonEncode(provisional.toJson()),
        ),
      );
      await _updateCache(userId, (cache) => _upsertNote(cache, provisional));
      await _emitSyncState();
      return provisional;
    }
  }

  @override
  Future<NoteAttachment> fetchAttachment(
    String noteId,
    String attachmentId,
  ) async {
    final userId = _userIdProvider();
    final cached = _findCachedNote(
      userId,
      noteId,
    )?.photoAttachments.where((entry) => entry.id == attachmentId).firstOrNull;
    if (cached?.dataBase64 != null) return cached!;
    final repository = _repository;
    if (repository is! NoteAttachmentsRepository) {
      throw const NotesPersistenceFailure();
    }
    final loaded = await (repository as NoteAttachmentsRepository)
        .fetchAttachment(noteId, attachmentId);
    final current = _findCachedNote(userId, noteId);
    if (current != null) {
      final updated = _withAttachmentData(current, [loaded]);
      await _updateCache(userId, (cache) => _upsertNote(cache, updated));
    }
    return loaded;
  }

  @override
  Future<Note> updateNote(String id, Map<String, dynamic> changes) async {
    final userId = _userIdProvider();
    final current = _findCachedNote(userId, id);
    final operationId =
        changes['clientMutationId'] as String? ?? const Uuid().v4();
    final expectedRevision =
        (changes['expectedRevision'] as num?)?.toInt() ?? current?.revision;
    final synchronizedChanges = Map<String, dynamic>.of(changes)
      ..['clientMutationId'] = operationId
      ..addAll({'expectedRevision': ?expectedRevision});
    try {
      final remote = await _repository.updateNote(id, synchronizedChanges);
      final note = _withAttachmentData(
        remote,
        _attachmentsFromChanges(
          synchronizedChanges,
          fallback: current?.photoAttachments ?? const [],
        ),
      );
      await _updateCache(userId, (cache) => _upsertNote(cache, note));
      return note;
    } catch (error) {
      if (userId == null || userId.isEmpty || current == null) rethrow;
      final remote = _conflictingNote(error);
      if (!_isRetryable(error) && remote == null) rethrow;
      final optimistic = _applyChanges(current, synchronizedChanges);
      await _queueUpdate(
        userId: userId,
        operationId: operationId,
        current: current,
        optimistic: optimistic,
        changes: synchronizedChanges,
        remote: remote,
      );
      await _updateCache(userId, (cache) => _upsertNote(cache, optimistic));
      await _emitSyncState();
      return optimistic;
    }
  }

  @override
  Future<Note> setNoteReaction(String id, String emoji, bool active) async {
    final userId = _userIdProvider();
    final current = _findCachedNote(userId, id);
    try {
      final note = await _repository.setNoteReaction(id, emoji, active);
      await _updateCache(userId, (cache) => _upsertNote(cache, note));
      return note;
    } catch (error) {
      if (userId == null || userId.isEmpty || current == null) rethrow;
      if (!_isRetryable(error)) rethrow;
      final optimistic = _applyReaction(
        current,
        emoji: emoji,
        active: active,
        userId: userId,
      );
      await _queueReaction(
        userId: userId,
        current: current,
        optimistic: optimistic,
        emoji: emoji,
        active: active,
      );
      await _updateCache(userId, (cache) => _upsertNote(cache, optimistic));
      await _emitSyncState();
      return optimistic;
    }
  }

  @override
  Future<List<Note>> reorderNotes(
    String boardId,
    List<String> orderedIds,
  ) async {
    final userId = _userIdProvider();
    final current = _cacheFor(userId)?.notesByBoard[boardId];
    try {
      final notes = await _sendReorderWithRebase(boardId, orderedIds);
      await _updateCache(userId, (cache) {
        cache.notesByBoard[boardId] = _sortedNotes(notes);
        cache.fullyLoadedBoardIds.add(boardId);
        _replaceKnownPinnedNotes(cache, notes);
        _replaceKnownReminderNotes(cache, notes);
      });
      return notes;
    } catch (error) {
      if (userId == null || userId.isEmpty || current == null) rethrow;
      if (!_isRetryable(error)) rethrow;
      final optimistic = _applyReorder(current, orderedIds);
      if (optimistic == null) rethrow;
      await _queueReorder(
        userId: userId,
        boardId: boardId,
        orderedIds: orderedIds,
      );
      await _updateCache(userId, (cache) {
        cache.notesByBoard[boardId] = _sortedNotes(optimistic);
        _replaceKnownPinnedNotes(cache, optimistic);
        _replaceKnownReminderNotes(cache, optimistic);
      });
      await _emitSyncState();
      return optimistic;
    }
  }

  @override
  Future<void> deleteNote(
    String id, {
    int? expectedRevision,
    String? clientMutationId,
  }) async {
    final userId = _userIdProvider();
    final current = _findCachedNote(userId, id);
    final operationId = clientMutationId ?? const Uuid().v4();
    final revision = expectedRevision ?? current?.revision;
    try {
      await _repository.deleteNote(
        id,
        expectedRevision: revision,
        clientMutationId: operationId,
      );
      await _updateCache(userId, (cache) => _removeNote(cache, id));
    } catch (error) {
      if (userId == null || userId.isEmpty || current == null) rethrow;
      final remote = _conflictingNote(error);
      if (!_isRetryable(error) && remote == null) rethrow;
      await _queueDelete(
        userId: userId,
        operationId: operationId,
        current: current,
        remote: remote,
      );
      await _updateCache(userId, (cache) => _removeNote(cache, id));
      await _emitSyncState();
    }
  }

  @override
  Future<GuestDataSyncResult> syncGuestData(LocalNotesSnapshot snapshot) async {
    final repository = _repository;
    if (repository is! GuestDataSyncTarget) {
      throw const NotesPersistenceFailure();
    }
    final userId = _userIdProvider();
    final result = await (repository as GuestDataSyncTarget).syncGuestData(
      snapshot,
    );
    await _updateCache(userId, (cache) {
      cache
        ..lists = []
        ..notesByBoard.clear()
        ..fullyLoadedBoardIds.clear()
        ..pinnedNotes = null
        ..reminderNotes = null;
    });
    return result;
  }

  @override
  Future<OfflineSyncSummary> offlineSyncSummary() async {
    final userId = _userIdProvider();
    if (userId == null || userId.isEmpty) return const OfflineSyncSummary();
    final mutations = await _mutationStore.listForUser(userId);
    return OfflineSyncSummary(
      pendingCount: mutations
          .where((item) => item.status == StoredMutationStatus.pending)
          .length,
      conflictCount: mutations
          .where((item) => item.status == StoredMutationStatus.conflict)
          .length,
      isSyncing: _isSyncing,
    );
  }

  @override
  Future<void> syncPendingChanges() async {
    final userId = _userIdProvider();
    if (_isSyncing || userId == null || userId.isEmpty) return;
    _isSyncing = true;
    await _emitSyncState();
    try {
      final mutations = await _mutationStore.listForUser(userId);
      final blockedBoardIds = mutations
          .where((item) => item.status == StoredMutationStatus.conflict)
          .map((item) => item.boardId)
          .toSet();
      for (final mutation in mutations.where(
        (item) => item.status == StoredMutationStatus.pending,
      )) {
        if (_userIdProvider() != userId) break;
        if (blockedBoardIds.contains(mutation.boardId)) continue;
        try {
          await _executeMutation(mutation);
          await _mutationStore.remove(mutation.id);
        } catch (error) {
          if (_isDeleteAlreadyApplied(mutation, error)) {
            await _mutationStore.remove(mutation.id);
            continue;
          }
          final remote = _conflictingNote(error);
          if (remote != null) {
            await _mutationStore.put(
              mutation.copyWith(
                status: StoredMutationStatus.conflict,
                remoteNoteJson: jsonEncode(remote.toJson()),
                errorMessage: 'La nota cambió en otro dispositivo.',
              ),
            );
            blockedBoardIds.add(mutation.boardId);
            continue;
          }
          if (_isRetryable(error)) break;
          if (_isReplayableIntent(mutation)) {
            await _mutationStore.remove(mutation.id);
            await _restoreBoardAfterDiscard(mutation);
            _events.add(
              OfflineSyncOperationDiscarded(
                mutation.kind == StoredMutationKind.reaction
                    ? 'No pudimos aplicar una reacción pendiente porque la nota cambió o dejó de estar disponible.'
                    : 'No pudimos conservar un orden pendiente porque la lista cambió en otro dispositivo.',
              ),
            );
            continue;
          }
          await _mutationStore.put(
            mutation.copyWith(
              status: StoredMutationStatus.conflict,
              errorMessage: 'El cambio necesita revisión antes de continuar.',
            ),
          );
          blockedBoardIds.add(mutation.boardId);
        }
      }
    } finally {
      _isSyncing = false;
      await _emitSyncState();
    }
  }

  @override
  Future<List<NoteSyncConflict>> fetchNoteSyncConflicts() async {
    final userId = _userIdProvider();
    if (userId == null || userId.isEmpty) return const [];
    final mutations = await _mutationStore.listForUser(userId);
    return mutations
        .where(
          (item) =>
              item.status == StoredMutationStatus.conflict &&
              item.localNoteJson != null &&
              item.remoteNoteJson != null,
        )
        .map(
          (item) => NoteSyncConflict(
            mutationId: item.id,
            kind: OfflineMutationKind.values.byName(item.kind.name),
            localNote: Note.fromJson(
              Map<String, dynamic>.from(jsonDecode(item.localNoteJson!) as Map),
            ),
            remoteNote: Note.fromJson(
              Map<String, dynamic>.from(
                jsonDecode(item.remoteNoteJson!) as Map,
              ),
            ),
          ),
        )
        .toList();
  }

  @override
  Future<void> resolveNoteSyncConflict(
    String mutationId,
    NoteConflictResolution resolution,
  ) async {
    final userId = _userIdProvider();
    if (userId == null || userId.isEmpty) return;
    final mutation = (await _mutationStore.listForUser(
      userId,
    )).where((item) => item.id == mutationId).firstOrNull;
    if (mutation == null) return;
    final remote = mutation.remoteNoteJson == null
        ? null
        : Note.fromJson(
            Map<String, dynamic>.from(
              jsonDecode(mutation.remoteNoteJson!) as Map,
            ),
          );
    if (resolution == NoteConflictResolution.keepRemote) {
      await _mutationStore.remove(mutation.id);
      if (remote != null) {
        await _updateCache(userId, (cache) => _upsertNote(cache, remote));
        _events.add(NoteChanged(remote));
      }
      await _emitSyncState();
      return;
    }
    if (remote == null) return;
    await _mutationStore.put(
      mutation.copyWith(
        baseRevision: remote.revision,
        status: StoredMutationStatus.pending,
        clearRemoteNote: true,
        clearError: true,
      ),
    );
    await _emitSyncState();
    await syncPendingChanges();
  }

  Future<void> _executeMutation(StoredOfflineMutation mutation) async {
    switch (mutation.kind) {
      case StoredMutationKind.create:
        final draft = NoteDraft.fromJson(
          Map<String, dynamic>.from(jsonDecode(mutation.payload) as Map),
        );
        final remote = await _repository.createNote(mutation.boardId, draft);
        final saved = _withAttachmentData(remote, draft.photoAttachments);
        await _updateCache(
          mutation.userId,
          (cache) => _upsertNote(cache, saved),
        );
        _events.add(NoteChanged(saved));
      case StoredMutationKind.update:
        final changes =
            Map<String, dynamic>.from(jsonDecode(mutation.payload) as Map)
              ..['expectedRevision'] = mutation.baseRevision
              ..['clientMutationId'] = mutation.id;
        final remote = await _repository.updateNote(mutation.entityId, changes);
        final saved = _withAttachmentData(
          remote,
          _attachmentsFromChanges(
            changes,
            fallback:
                _findCachedNote(
                  mutation.userId,
                  mutation.entityId,
                )?.photoAttachments ??
                const [],
          ),
        );
        await _updateCache(
          mutation.userId,
          (cache) => _upsertNote(cache, saved),
        );
        _events.add(NoteChanged(saved));
      case StoredMutationKind.delete:
        await _repository.deleteNote(
          mutation.entityId,
          expectedRevision: mutation.baseRevision,
          clientMutationId: mutation.id,
        );
        await _updateCache(
          mutation.userId,
          (cache) => _removeNote(cache, mutation.entityId),
        );
        _events.add(NoteRemoved(mutation.entityId, mutation.boardId));
      case StoredMutationKind.reaction:
        final payload = Map<String, dynamic>.from(
          jsonDecode(mutation.payload) as Map,
        );
        final saved = await _repository.setNoteReaction(
          mutation.entityId,
          payload['emoji']! as String,
          payload['active']! as bool,
        );
        await _updateCache(
          mutation.userId,
          (cache) => _upsertNote(cache, saved),
        );
        _events.add(NoteChanged(saved));
      case StoredMutationKind.reorder:
        final payload = Map<String, dynamic>.from(
          jsonDecode(mutation.payload) as Map,
        );
        final orderedIds = List<String>.from(
          payload['orderedIds'] as List<dynamic>,
        );
        final saved = await _sendReorderWithRebase(
          mutation.boardId,
          orderedIds,
        );
        await _updateCache(mutation.userId, (cache) {
          cache.notesByBoard[mutation.boardId] = _sortedNotes(saved);
          cache.fullyLoadedBoardIds.add(mutation.boardId);
          _replaceKnownPinnedNotes(cache, saved);
          _replaceKnownReminderNotes(cache, saved);
        });
        _events.add(NotesReordered(mutation.boardId, saved));
    }
  }

  Future<void> _queueUpdate({
    required String userId,
    required String operationId,
    required Note current,
    required Note optimistic,
    required Map<String, dynamic> changes,
    required Note? remote,
  }) async {
    final storedChanges = Map<String, dynamic>.of(changes)
      ..remove('expectedRevision')
      ..remove('clientMutationId');
    final mutations = await _mutationStore.listForUser(userId);
    final noteMutations = mutations
        .where((item) => item.entityId == current.id)
        .toList();
    final existingCreate = noteMutations
        .where((item) => item.kind == StoredMutationKind.create)
        .firstOrNull;
    if (existingCreate != null) {
      final draft = Map<String, dynamic>.from(
        jsonDecode(existingCreate.payload) as Map,
      )..addAll(storedChanges);
      await _mutationStore.put(
        existingCreate.copyWith(
          payload: jsonEncode(draft),
          localNoteJson: jsonEncode(optimistic.toJson()),
        ),
      );
      return;
    }
    final existingUpdate = noteMutations
        .where((item) => item.kind == StoredMutationKind.update)
        .lastOrNull;
    if (existingUpdate != null) {
      final merged = Map<String, dynamic>.from(
        jsonDecode(existingUpdate.payload) as Map,
      )..addAll(storedChanges);
      await _mutationStore.put(
        existingUpdate.copyWith(
          payload: jsonEncode(merged),
          status: remote == null
              ? existingUpdate.status
              : StoredMutationStatus.conflict,
          localNoteJson: jsonEncode(optimistic.toJson()),
          remoteNoteJson: remote == null ? null : jsonEncode(remote.toJson()),
        ),
      );
      return;
    }
    await _mutationStore.put(
      StoredOfflineMutation(
        id: operationId,
        userId: userId,
        entityId: current.id,
        boardId: current.boardId,
        kind: StoredMutationKind.update,
        payload: jsonEncode(storedChanges),
        baseRevision: current.revision,
        createdAt: DateTime.now(),
        status: remote == null
            ? StoredMutationStatus.pending
            : StoredMutationStatus.conflict,
        localNoteJson: jsonEncode(optimistic.toJson()),
        remoteNoteJson: remote == null ? null : jsonEncode(remote.toJson()),
      ),
    );
  }

  Future<void> _queueReaction({
    required String userId,
    required Note current,
    required Note optimistic,
    required String emoji,
    required bool active,
  }) async {
    final mutations = await _mutationStore.listForUser(userId);
    for (final mutation in mutations.where(
      (item) =>
          item.entityId == current.id &&
          item.kind == StoredMutationKind.reaction,
    )) {
      try {
        final payload = Map<String, dynamic>.from(
          jsonDecode(mutation.payload) as Map,
        );
        if (payload['emoji'] == emoji) {
          await _mutationStore.remove(mutation.id);
        }
      } on Object {
        await _mutationStore.remove(mutation.id);
      }
    }
    await _mutationStore.put(
      StoredOfflineMutation(
        id: const Uuid().v4(),
        userId: userId,
        entityId: current.id,
        boardId: current.boardId,
        kind: StoredMutationKind.reaction,
        payload: jsonEncode({'emoji': emoji, 'active': active}),
        baseRevision: current.revision,
        createdAt: DateTime.now(),
        localNoteJson: jsonEncode(optimistic.toJson()),
      ),
    );
  }

  Future<void> _queueReorder({
    required String userId,
    required String boardId,
    required List<String> orderedIds,
  }) async {
    final mutations = await _mutationStore.listForUser(userId);
    for (final mutation in mutations.where(
      (item) =>
          item.boardId == boardId && item.kind == StoredMutationKind.reorder,
    )) {
      await _mutationStore.remove(mutation.id);
    }
    await _mutationStore.put(
      StoredOfflineMutation(
        id: const Uuid().v4(),
        userId: userId,
        entityId: boardId,
        boardId: boardId,
        kind: StoredMutationKind.reorder,
        payload: jsonEncode({'orderedIds': orderedIds}),
        baseRevision: 0,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> _queueDelete({
    required String userId,
    required String operationId,
    required Note current,
    required Note? remote,
  }) async {
    final existing = (await _mutationStore.listForUser(
      userId,
    )).where((item) => item.entityId == current.id).toList();
    if (existing.any((item) => item.kind == StoredMutationKind.create)) {
      for (final item in existing) {
        await _mutationStore.remove(item.id);
      }
      return;
    }
    for (final item in existing) {
      await _mutationStore.remove(item.id);
    }
    await _mutationStore.put(
      StoredOfflineMutation(
        id: operationId,
        userId: userId,
        entityId: current.id,
        boardId: current.boardId,
        kind: StoredMutationKind.delete,
        payload: '{}',
        baseRevision: current.revision,
        createdAt: DateTime.now(),
        status: remote == null
            ? StoredMutationStatus.pending
            : StoredMutationStatus.conflict,
        localNoteJson: jsonEncode(current.toJson()),
        remoteNoteJson: remote == null ? null : jsonEncode(remote.toJson()),
      ),
    );
  }

  Note _applyChanges(Note current, Map<String, dynamic> changes) {
    final json = current.toJson()
      ..addAll(changes)
      ..remove('expectedRevision')
      ..remove('clientMutationId')
      ..['updatedAt'] = DateTime.now().toIso8601String();
    return Note.fromJson(json);
  }

  static List<NoteAttachment> _attachmentsFromChanges(
    Map<String, dynamic> changes, {
    required List<NoteAttachment> fallback,
  }) {
    final raw = changes['attachments'];
    if (raw is! List) return fallback;
    final fallbackById = {for (final entry in fallback) entry.id: entry};
    return raw.whereType<Map>().map((entry) {
      final attachment = NoteAttachment.fromJson(
        Map<String, dynamic>.from(entry),
      );
      final cached = fallbackById[attachment.id];
      return attachment.dataBase64 != null || cached?.dataBase64 == null
          ? attachment
          : attachment.copyWith(dataBase64: cached!.dataBase64);
    }).toList();
  }

  static Note _preserveAttachmentData(Note remote, Note? cached) =>
      cached == null
      ? remote
      : _withAttachmentData(remote, cached.photoAttachments);

  static Note _withAttachmentData(
    Note note,
    Iterable<NoteAttachment> localAttachments,
  ) {
    final localById = {
      for (final attachment in localAttachments)
        if (attachment.dataBase64 != null) attachment.id: attachment,
    };
    if (localById.isEmpty) return note;
    return note.copyWith(
      attachments: note.photoAttachments.map((attachment) {
        final local = localById[attachment.id];
        return local == null
            ? attachment
            : attachment.copyWith(dataBase64: local.dataBase64);
      }).toList(),
    );
  }

  Note _applyReaction(
    Note current, {
    required String emoji,
    required bool active,
    required String userId,
  }) {
    final reactions = List<NoteReaction>.of(current.reactions);
    final index = reactions.indexWhere((reaction) => reaction.emoji == emoji);
    final users = index == -1 ? <String>{} : reactions[index].userUids.toSet();
    if (active) {
      users.add(userId);
    } else {
      users.remove(userId);
    }
    if (users.isEmpty) {
      if (index != -1) reactions.removeAt(index);
    } else {
      final reaction = NoteReaction(
        emoji: emoji,
        userUids: users.toList()..sort(),
      );
      if (index == -1) {
        reactions.add(reaction);
      } else {
        reactions[index] = reaction;
      }
    }
    reactions.sort(
      (a, b) => supportedNoteReactionEmojis
          .indexOf(a.emoji)
          .compareTo(supportedNoteReactionEmojis.indexOf(b.emoji)),
    );
    return current.copyWith(reactions: reactions, updatedAt: DateTime.now());
  }

  List<Note>? _applyReorder(List<Note> current, List<String> orderedIds) {
    if (current.length != orderedIds.length ||
        current.map((note) => note.id).toSet().length != current.length ||
        orderedIds.toSet().length != orderedIds.length) {
      return null;
    }
    final notesById = {for (final note in current) note.id: note};
    if (orderedIds.any((id) => !notesById.containsKey(id))) return null;
    final now = DateTime.now();
    return [
      for (final entry in orderedIds.indexed)
        notesById[entry.$2]!.copyWith(sortOrder: entry.$1, updatedAt: now),
    ]..sort(compareNotes);
  }

  Future<List<Note>> _sendReorderWithRebase(
    String boardId,
    List<String> orderedIds,
  ) async {
    try {
      return await _repository.reorderNotes(boardId, orderedIds);
    } on DioException catch (error) {
      if (error.response?.statusCode != 400) rethrow;
      final remoteNotes = await _repository.fetchNotes(boardId);
      final rebasedIds = _rebaseOrder(remoteNotes, orderedIds);
      final remoteIds = _sortedNotes(
        remoteNotes,
      ).map((note) => note.id).toList();
      if (_sameOrder(remoteIds, rebasedIds)) return remoteNotes;
      return _repository.reorderNotes(boardId, rebasedIds);
    }
  }

  List<String> _rebaseOrder(List<Note> remoteNotes, List<String> orderedIds) {
    final sortedRemote = _sortedNotes(remoteNotes);
    final notesById = {for (final note in sortedRemote) note.id: note};
    final desired = orderedIds.where(notesById.containsKey).toList();
    final desiredSet = desired.toSet();
    final newNotes = sortedRemote.where(
      (note) => !desiredSet.contains(note.id),
    );
    return [
      ...desired.where((id) => notesById[id]!.isPinned),
      ...newNotes.where((note) => note.isPinned).map((note) => note.id),
      ...desired.where((id) => !notesById[id]!.isPinned),
      ...newNotes.where((note) => !note.isPinned).map((note) => note.id),
    ];
  }

  bool _sameOrder(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

  bool _isReplayableIntent(StoredOfflineMutation mutation) =>
      mutation.kind == StoredMutationKind.reaction ||
      mutation.kind == StoredMutationKind.reorder;

  Future<void> _restoreBoardAfterDiscard(StoredOfflineMutation mutation) async {
    try {
      final notes = await _repository.fetchNotes(mutation.boardId);
      await _updateCache(mutation.userId, (cache) {
        cache.notesByBoard[mutation.boardId] = _sortedNotes(notes);
        _replaceKnownPinnedNotes(cache, notes);
        _replaceKnownReminderNotes(cache, notes);
      });
      _events.add(NotesReordered(mutation.boardId, notes));
    } on Object {
      // Access may have been removed; the realtime access event will clean up.
    }
  }

  Note? _findCachedNote(String? userId, String id) {
    final cache = _cacheFor(userId);
    if (cache == null) return null;
    for (final notes in cache.notesByBoard.values) {
      final match = notes.where((note) => note.id == id).firstOrNull;
      if (match != null) return match;
    }
    return cache.pinnedNotes?.where((note) => note.id == id).firstOrNull ??
        cache.reminderNotes?.where((note) => note.id == id).firstOrNull;
  }

  Note? _conflictingNote(Object error) {
    if (error is! DioException || error.response?.statusCode != 409) {
      return null;
    }
    final data = error.response?.data;
    if (data is! Map || data['current'] is! Map) return null;
    return Note.fromJson(Map<String, dynamic>.from(data['current'] as Map));
  }

  bool _isRetryable(Object error) {
    if (error is! DioException) return false;
    if (error.response?.statusCode case final status? when status >= 500) {
      return true;
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.transformTimeout ||
      DioExceptionType.connectionError => true,
      _ => false,
    };
  }

  bool _isDeleteAlreadyApplied(StoredOfflineMutation mutation, Object error) =>
      mutation.kind == StoredMutationKind.delete &&
      error is DioException &&
      error.response?.statusCode == 404;

  Future<void> _emitSyncState() async {
    final summary = await offlineSyncSummary();
    _events.add(
      OfflineSyncStateChanged(
        pendingCount: summary.pendingCount,
        conflictCount: summary.conflictCount,
        isSyncing: summary.isSyncing,
      ),
    );
  }

  void _onRealtimeEvent(NotesRealtimeEvent event) {
    final userId = _userIdProvider();
    switch (event) {
      case NoteChanged(:final note):
        final merged = _preserveAttachmentData(
          note,
          _findCachedNote(userId, note.id),
        );
        unawaited(_updateCache(userId, (cache) => _upsertNote(cache, merged)));
      case NoteRemoved(:final id):
        unawaited(_updateCache(userId, (cache) => _removeNote(cache, id)));
      case NotesReordered(:final boardId, :final notes):
        unawaited(
          _updateCache(userId, (cache) {
            final cachedById = {
              for (final note in cache.notesByBoard[boardId] ?? const <Note>[])
                note.id: note,
            };
            final merged = notes
                .map(
                  (note) => _preserveAttachmentData(note, cachedById[note.id]),
                )
                .toList();
            cache.notesByBoard[boardId] = _sortedNotes(merged);
            cache.fullyLoadedBoardIds.add(boardId);
            _replaceKnownPinnedNotes(cache, merged);
            _replaceKnownReminderNotes(cache, merged);
          }),
        );
      case ListAppearanceChanged(:final listId, :final appearance):
        unawaited(
          _updateCache(userId, (cache) {
            final index = cache.lists.indexWhere((list) => list.id == listId);
            if (index != -1) {
              cache.lists[index] = cache.lists[index].copyWith(
                appearance: appearance,
              );
            }
          }),
        );
      case ListNameChanged(:final listId, :final name, :final updatedAt):
        unawaited(
          _updateCache(userId, (cache) {
            final index = cache.lists.indexWhere((list) => list.id == listId);
            if (index != -1) {
              cache.lists[index] = cache.lists[index].copyWith(
                name: name,
                updatedAt: updatedAt,
              );
            }
          }),
        );
      case AggregateBoardAppearanceChanged(:final scope, :final appearance):
        unawaited(
          _updateCache(userId, (cache) {
            cache.aggregateBoardAppearances =
                (cache.aggregateBoardAppearances ??
                        const AggregateBoardAppearances())
                    .copyWithScope(scope, appearance);
          }),
        );
      case ListAccessRemoved(:final listId):
        unawaited(_updateCache(userId, (cache) => _removeList(cache, listId)));
      case ListKeyShareRequested() || ListKeyEnvelopeUpdated():
        break;
      case RealtimeConnectionChanged() ||
          RealtimeConnectionAttemptStarted() ||
          NotesSourceChanged() ||
          GuestDataSyncStarted() ||
          GuestDataSyncCompleted() ||
          GuestDataSyncFailed():
        break;
      case OfflineSyncStateChanged():
        break;
      case OfflineSyncOperationDiscarded():
        break;
    }
    if (event case RealtimeConnectionChanged(isConnected: true)) {
      unawaited(syncPendingChanges());
    }
    _events.add(event);
  }

  Future<void> _updateCache(
    String? userId,
    void Function(_AccountNotesCache cache) update,
  ) {
    if (userId == null || userId.isEmpty) return Future.value();
    final operation = _writeQueue.then((_) async {
      if (_userIdProvider() != userId) return;
      final cache = _cacheFor(userId, create: true)!;
      update(cache);
      try {
        await _preferences.setString(storageKey, jsonEncode(cache.toJson()));
      } on Object {
        // Cache persistence must never turn a successful server operation into
        // an application error.
      }
    });
    _writeQueue = operation.catchError((_) {});
    return operation.catchError((_) {});
  }

  _AccountNotesCache? _cacheFor(String? userId, {bool create = false}) {
    if (userId == null || userId.isEmpty) return null;
    if (_loadedUserId == userId) {
      if (_cache == null && create) _cache = _AccountNotesCache(userId: userId);
      return _cache;
    }

    _loadedUserId = userId;
    _cache = null;
    final stored = _preferences.getString(storageKey);
    if (stored != null) {
      try {
        final json = Map<String, dynamic>.from(jsonDecode(stored) as Map);
        if (json['userId'] == userId) {
          _cache = _AccountNotesCache.fromJson(json);
        }
      } on Object {
        _cache = null;
      }
    }
    if (_cache == null && create) _cache = _AccountNotesCache(userId: userId);
    return _cache;
  }

  static void _replaceList(_AccountNotesCache cache, NoteList list) {
    final index = cache.lists.indexWhere((item) => item.id == list.id);
    if (index == -1) {
      if (cache.lists.isNotEmpty) cache.lists.add(list);
    } else {
      cache.lists[index] = list;
    }
  }

  static void _removeList(_AccountNotesCache cache, String listId) {
    cache.lists.removeWhere((list) => list.id == listId);
    cache.notesByBoard.remove(listId);
    cache.fullyLoadedBoardIds.remove(listId);
    cache.pinnedNotes?.removeWhere((note) => note.boardId == listId);
    cache.reminderNotes?.removeWhere((note) => note.boardId == listId);
  }

  static void _upsertNote(_AccountNotesCache cache, Note note) {
    final boardNotes = cache.notesByBoard.putIfAbsent(note.boardId, () => []);
    {
      final index = boardNotes.indexWhere((item) => item.id == note.id);
      if (index == -1) {
        boardNotes.add(note);
      } else {
        boardNotes[index] = note;
      }
      boardNotes.sort(compareNotes);
    }

    final pinnedNotes = cache.pinnedNotes;
    if (pinnedNotes != null) {
      final pinnedIndex = pinnedNotes.indexWhere((item) => item.id == note.id);
      if (note.isPinned) {
        if (pinnedIndex == -1) {
          pinnedNotes.add(note);
        } else {
          pinnedNotes[pinnedIndex] = note;
        }
      } else if (pinnedIndex != -1) {
        pinnedNotes.removeAt(pinnedIndex);
      }
      pinnedNotes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }

    final reminderNotes = cache.reminderNotes;
    if (reminderNotes != null) {
      final reminderIndex = reminderNotes.indexWhere(
        (item) => item.id == note.id,
      );
      if (note.reminderAt != null) {
        if (reminderIndex == -1) {
          reminderNotes.add(note);
        } else {
          reminderNotes[reminderIndex] = note;
        }
      } else if (reminderIndex != -1) {
        reminderNotes.removeAt(reminderIndex);
      }
      reminderNotes.sort(_compareReminderNotes);
    }
  }

  static void _replaceKnownPinnedNotes(
    _AccountNotesCache cache,
    List<Note> notes,
  ) {
    if (cache.pinnedNotes == null) return;
    for (final note in notes) {
      _upsertNote(cache, note);
    }
  }

  static void _replaceKnownReminderNotes(
    _AccountNotesCache cache,
    List<Note> notes,
  ) {
    if (cache.reminderNotes == null) return;
    for (final note in notes) {
      _upsertNote(cache, note);
    }
  }

  static void _removeNote(_AccountNotesCache cache, String id) {
    for (final notes in cache.notesByBoard.values) {
      notes.removeWhere((note) => note.id == id);
    }
    cache.pinnedNotes?.removeWhere((note) => note.id == id);
    cache.reminderNotes?.removeWhere((note) => note.id == id);
  }

  static List<Note> _sortedNotes(Iterable<Note> notes) =>
      List<Note>.of(notes)..sort(compareNotes);

  static List<Note> _sortedPinnedNotes(Iterable<Note> notes) =>
      List<Note>.of(notes)..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  static List<Note> _sortedReminderNotes(Iterable<Note> notes) =>
      List<Note>.of(notes)..sort(_compareReminderNotes);

  @override
  void dispose() {
    unawaited(_realtimeSubscription.cancel());
    _repository.dispose();
    unawaited(_mutationStore.close());
    unawaited(_events.close());
  }
}

class _AccountNotesCache {
  _AccountNotesCache({
    required this.userId,
    List<NoteList>? lists,
    Map<String, List<Note>>? notesByBoard,
    Set<String>? fullyLoadedBoardIds,
    this.pinnedNotes,
    this.reminderNotes,
    this.aggregateBoardAppearances,
  }) : lists = lists ?? [],
       notesByBoard = notesByBoard ?? {},
       fullyLoadedBoardIds = fullyLoadedBoardIds ?? {};

  factory _AccountNotesCache.fromJson(Map<String, dynamic> json) {
    final rawNotesByBoard = Map<String, dynamic>.from(
      json['notesByBoard'] as Map? ?? const {},
    );
    final rawPinnedNotes = json['pinnedNotes'];
    final rawReminderNotes = json['reminderNotes'];
    final rawAggregateBoardAppearances = json['aggregateBoardAppearances'];
    return _AccountNotesCache(
      userId: json['userId'] as String,
      lists: (json['lists'] as List<dynamic>? ?? const [])
          .map(
            (item) => NoteList.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
      notesByBoard: {
        for (final entry in rawNotesByBoard.entries)
          entry.key: (entry.value as List<dynamic>)
              .map(
                (item) => Note.fromJson(Map<String, dynamic>.from(item as Map)),
              )
              .toList(),
      },
      fullyLoadedBoardIds: json['fullyLoadedBoardIds'] is List
          ? Set<String>.from(json['fullyLoadedBoardIds'] as List<dynamic>)
          : rawNotesByBoard.keys.toSet(),
      pinnedNotes: rawPinnedNotes is List
          ? rawPinnedNotes
                .map(
                  (item) =>
                      Note.fromJson(Map<String, dynamic>.from(item as Map)),
                )
                .toList()
          : null,
      reminderNotes: rawReminderNotes is List
          ? rawReminderNotes
                .map(
                  (item) =>
                      Note.fromJson(Map<String, dynamic>.from(item as Map)),
                )
                .toList()
          : null,
      aggregateBoardAppearances: rawAggregateBoardAppearances is Map
          ? AggregateBoardAppearances.fromJson(
              Map<String, dynamic>.from(rawAggregateBoardAppearances),
            )
          : null,
    );
  }

  final String userId;
  List<NoteList> lists;
  final Map<String, List<Note>> notesByBoard;
  final Set<String> fullyLoadedBoardIds;
  List<Note>? pinnedNotes;
  List<Note>? reminderNotes;
  AggregateBoardAppearances? aggregateBoardAppearances;

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'lists': lists.map((list) => list.toJson()).toList(),
    'notesByBoard': {
      for (final entry in notesByBoard.entries)
        entry.key: entry.value.map((note) => note.toJson()).toList(),
    },
    'fullyLoadedBoardIds': fullyLoadedBoardIds.toList()..sort(),
    if (pinnedNotes != null)
      'pinnedNotes': pinnedNotes!.map((note) => note.toJson()).toList(),
    if (reminderNotes != null)
      'reminderNotes': reminderNotes!.map((note) => note.toJson()).toList(),
    if (aggregateBoardAppearances != null)
      'aggregateBoardAppearances': aggregateBoardAppearances!.toJson(),
  };
}

int _compareReminderNotes(Note a, Note b) {
  final byReminder = a.reminderAt!.compareTo(b.reminderAt!);
  return byReminder != 0 ? byReminder : b.updatedAt.compareTo(a.updatedAt);
}
