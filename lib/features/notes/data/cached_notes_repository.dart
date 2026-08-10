import 'dart:async';
import 'dart:convert';

import 'package:nocknock/features/notes/data/notes_repository.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        E2eeNotesTransport {
  factory CachedNotesRepository({
    required NotesRepository repository,
    required SharedPreferences preferences,
    required NotesCacheUserIdProvider userIdProvider,
  }) => CachedNotesRepository._(repository, preferences, userIdProvider);

  CachedNotesRepository._(
    this._repository,
    this._preferences,
    this._userIdProvider,
  ) {
    _realtimeSubscription = _repository.realtimeEvents.listen(_onRealtimeEvent);
  }

  static const storageKey = 'nocknock.account_notes_cache.v1';

  final NotesRepository _repository;
  final SharedPreferences _preferences;
  final NotesCacheUserIdProvider _userIdProvider;
  final _events = StreamController<NotesRealtimeEvent>.broadcast();

  late final StreamSubscription<NotesRealtimeEvent> _realtimeSubscription;
  Future<void> _writeQueue = Future.value();
  String? _loadedUserId;
  _AccountNotesCache? _cache;

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
    );
  }

  @override
  Future<void> connect(String boardId) => _repository.connect(boardId);

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
        cache.pinnedNotes?.removeWhere(
          (note) => !validIds.contains(note.boardId),
        );
      }),
    );
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
  Future<List<Note>> fetchNotes(String boardId) async {
    final userId = _userIdProvider();
    final notes = await _repository.fetchNotes(boardId);
    unawaited(
      _updateCache(userId, (cache) {
        cache.notesByBoard[boardId] = _sortedNotes(notes);
      }),
    );
    return notes;
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
  Future<Note> createNote(String boardId, NoteDraft draft) async {
    final userId = _userIdProvider();
    final note = await _repository.createNote(boardId, draft);
    unawaited(_updateCache(userId, (cache) => _upsertNote(cache, note)));
    return note;
  }

  @override
  Future<Note> updateNote(String id, Map<String, dynamic> changes) async {
    final userId = _userIdProvider();
    final note = await _repository.updateNote(id, changes);
    unawaited(_updateCache(userId, (cache) => _upsertNote(cache, note)));
    return note;
  }

  @override
  Future<List<Note>> reorderNotes(
    String boardId,
    List<String> orderedIds,
  ) async {
    final userId = _userIdProvider();
    final notes = await _repository.reorderNotes(boardId, orderedIds);
    unawaited(
      _updateCache(userId, (cache) {
        cache.notesByBoard[boardId] = _sortedNotes(notes);
        _replaceKnownPinnedNotes(cache, notes);
      }),
    );
    return notes;
  }

  @override
  Future<void> deleteNote(String id) async {
    final userId = _userIdProvider();
    await _repository.deleteNote(id);
    unawaited(_updateCache(userId, (cache) => _removeNote(cache, id)));
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
        ..pinnedNotes = null;
    });
    return result;
  }

  void _onRealtimeEvent(NotesRealtimeEvent event) {
    final userId = _userIdProvider();
    switch (event) {
      case NoteChanged(:final note):
        unawaited(_updateCache(userId, (cache) => _upsertNote(cache, note)));
      case NoteRemoved(:final id):
        unawaited(_updateCache(userId, (cache) => _removeNote(cache, id)));
      case NotesReordered(:final boardId, :final notes):
        unawaited(
          _updateCache(userId, (cache) {
            cache.notesByBoard[boardId] = _sortedNotes(notes);
            _replaceKnownPinnedNotes(cache, notes);
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
      case ListAccessRemoved(:final listId):
        unawaited(_updateCache(userId, (cache) => _removeList(cache, listId)));
      case RealtimeConnectionChanged() ||
          NotesSourceChanged() ||
          GuestDataSyncStarted() ||
          GuestDataSyncCompleted() ||
          GuestDataSyncFailed():
        break;
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
    cache.pinnedNotes?.removeWhere((note) => note.boardId == listId);
  }

  static void _upsertNote(_AccountNotesCache cache, Note note) {
    final boardNotes = cache.notesByBoard[note.boardId];
    if (boardNotes != null) {
      final index = boardNotes.indexWhere((item) => item.id == note.id);
      if (index == -1) {
        boardNotes.add(note);
      } else {
        boardNotes[index] = note;
      }
      boardNotes.sort(compareNotes);
    }

    final pinnedNotes = cache.pinnedNotes;
    if (pinnedNotes == null) return;
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

  static void _replaceKnownPinnedNotes(
    _AccountNotesCache cache,
    List<Note> notes,
  ) {
    if (cache.pinnedNotes == null) return;
    for (final note in notes) {
      _upsertNote(cache, note);
    }
  }

  static void _removeNote(_AccountNotesCache cache, String id) {
    for (final notes in cache.notesByBoard.values) {
      notes.removeWhere((note) => note.id == id);
    }
    cache.pinnedNotes?.removeWhere((note) => note.id == id);
  }

  static List<Note> _sortedNotes(Iterable<Note> notes) =>
      List<Note>.of(notes)..sort(compareNotes);

  static List<Note> _sortedPinnedNotes(Iterable<Note> notes) =>
      List<Note>.of(notes)..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  void dispose() {
    unawaited(_realtimeSubscription.cancel());
    _repository.dispose();
    unawaited(_events.close());
  }
}

class _AccountNotesCache {
  _AccountNotesCache({
    required this.userId,
    List<NoteList>? lists,
    Map<String, List<Note>>? notesByBoard,
    this.pinnedNotes,
  }) : lists = lists ?? [],
       notesByBoard = notesByBoard ?? {};

  factory _AccountNotesCache.fromJson(Map<String, dynamic> json) {
    final rawNotesByBoard = Map<String, dynamic>.from(
      json['notesByBoard'] as Map? ?? const {},
    );
    final rawPinnedNotes = json['pinnedNotes'];
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
      pinnedNotes: rawPinnedNotes is List
          ? rawPinnedNotes
                .map(
                  (item) =>
                      Note.fromJson(Map<String, dynamic>.from(item as Map)),
                )
                .toList()
          : null,
    );
  }

  final String userId;
  List<NoteList> lists;
  final Map<String, List<Note>> notesByBoard;
  List<Note>? pinnedNotes;

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'lists': lists.map((list) => list.toJson()).toList(),
    'notesByBoard': {
      for (final entry in notesByBoard.entries)
        entry.key: entry.value.map((note) => note.toJson()).toList(),
    },
    if (pinnedNotes != null)
      'pinnedNotes': pinnedNotes!.map((note) => note.toJson()).toList(),
  };
}
