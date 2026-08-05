import 'dart:async';
import 'dart:convert';

import 'package:nocknock/features/notes/data/notes_repository.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

typedef PreferencesLoader = Future<SharedPreferences> Function();

/// Persists guest notes in this installation only.
class LocalNotesRepository
    implements NotesRepository, LocalNotesDataCleaner, LocalNotesDataReader {
  LocalNotesRepository({
    PreferencesLoader? preferencesLoader,
    this.uuid = const Uuid(),
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const _storageKey = 'nocknock.guest_notes.v1';

  final PreferencesLoader _preferencesLoader;
  final Uuid uuid;
  final _events = StreamController<NotesRealtimeEvent>.broadcast();

  SharedPreferences? _preferences;
  List<NoteList>? _lists;
  List<Note>? _notes;

  @override
  Stream<NotesRealtimeEvent> get realtimeEvents => _events.stream;

  @override
  Future<void> connect(String boardId) async {}

  @override
  void disconnect() {}

  @override
  Future<List<NoteList>> fetchLists() async {
    await _ensureLoaded();
    return List.unmodifiable(_lists!);
  }

  @override
  Future<NoteList> createList(String name) async {
    await _ensureLoaded();
    final now = DateTime.now();
    final list = NoteList(
      id: 'local-list-${uuid.v4()}',
      name: name.trim(),
      createdAt: now,
      updatedAt: now,
    );
    _lists!.add(list);
    await _persist();
    return list;
  }

  @override
  Future<NoteList> updateList(String listId, String name) async {
    await _ensureLoaded();
    final index = _lists!.indexWhere((list) => list.id == listId);
    if (index == -1) throw const NotesPersistenceFailure();
    final previous = _lists![index];
    final updated = previous.copyWith(
      name: name.trim(),
      updatedAt: DateTime.now(),
    );
    _lists![index] = updated;
    try {
      await _persist();
    } catch (_) {
      _lists![index] = previous;
      rethrow;
    }
    return updated;
  }

  @override
  Future<void> deleteList(String listId) async {
    await _ensureLoaded();
    final previousLists = List<NoteList>.of(_lists!);
    final previousNotes = List<Note>.of(_notes!);
    if (!_lists!.any((list) => list.id == listId)) {
      throw const NotesPersistenceFailure();
    }
    _lists!.removeWhere((list) => list.id == listId);
    _notes!.removeWhere((note) => note.boardId == listId);
    try {
      await _persist();
    } catch (_) {
      _lists = previousLists;
      _notes = previousNotes;
      rethrow;
    }
  }

  @override
  Future<NoteList> inviteCollaborator(String listId, String email) =>
      throw const CollaborationRequiresSignInFailure();

  @override
  Future<NoteList> removeCollaborator(String listId, String collaboratorUid) =>
      throw const CollaborationRequiresSignInFailure();

  @override
  Future<NoteList> updateListAppearance(
    String listId,
    ListAppearance appearance,
  ) async {
    await _ensureLoaded();
    final index = _lists!.indexWhere((list) => list.id == listId);
    if (index == -1) throw const NotesPersistenceFailure();
    final previous = _lists![index];
    final updated = _lists![index].copyWith(appearance: appearance);
    _lists![index] = updated;
    try {
      await _persist();
    } catch (_) {
      _lists![index] = previous;
      rethrow;
    }
    return updated;
  }

  @override
  Future<List<Note>> fetchNotes(String boardId) async {
    await _ensureLoaded();
    final notes = _notes!.where((note) => note.boardId == boardId).toList()
      ..sort(compareNotes);
    return List.unmodifiable(notes);
  }

  @override
  Future<List<Note>> fetchPinnedNotes() async {
    await _ensureLoaded();
    final notes = _notes!.where((note) => note.isPinned).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List.unmodifiable(notes);
  }

  @override
  Future<Note> createNote(String boardId, NoteDraft draft) async {
    await _ensureLoaded();
    final now = DateTime.now();
    final note = Note(
      id: 'local-note-${uuid.v4()}',
      boardId: boardId,
      title: draft.title,
      content: draft.content,
      contentDelta: draft.contentDelta,
      color: draft.color,
      category: draft.category,
      checklist: draft.checklist,
      authorName: draft.authorName,
      assigneeUid: draft.assigneeUid,
      isCompleted: false,
      sortOrder: -now.microsecondsSinceEpoch,
      positionX: 0,
      positionY: 0,
      reminderAt: draft.reminderAt,
      createdAt: now,
      updatedAt: now,
    );
    _notes!.add(note);
    await _persist();
    return note;
  }

  @override
  Future<Note> updateNote(String id, Map<String, dynamic> changes) async {
    await _ensureLoaded();
    final index = _notes!.indexWhere((note) => note.id == id);
    if (index == -1) throw const NotesPersistenceFailure();

    final existing = _notes![index];
    final note = Note(
      id: existing.id,
      boardId: existing.boardId,
      title: changes['title'] as String? ?? existing.title,
      content: changes['content'] as String? ?? existing.content,
      contentDelta: changes.containsKey('contentDelta')
          ? changes['contentDelta'] as String?
          : existing.contentDelta,
      color: changes['color'] == null
          ? existing.color
          : NoteColor.values.firstWhere(
              (color) => color.name == changes['color'],
              orElse: () => existing.color,
            ),
      category: changes['category'] == null
          ? existing.category
          : NoteCategory.values.firstWhere(
              (category) => category.name == changes['category'],
              orElse: () => existing.category,
            ),
      checklist: changes['checklist'] == null
          ? existing.checklist
          : (changes['checklist'] as List<dynamic>)
                .map(
                  (item) => NoteChecklistItem.fromJson(
                    Map<String, dynamic>.from(item as Map),
                  ),
                )
                .toList(),
      authorName: changes['authorName'] as String? ?? existing.authorName,
      assigneeUid: changes.containsKey('assigneeUid')
          ? changes['assigneeUid'] as String?
          : existing.assigneeUid,
      isCompleted: changes['isCompleted'] as bool? ?? existing.isCompleted,
      isPinned: changes['isPinned'] as bool? ?? existing.isPinned,
      sortOrder: (changes['sortOrder'] as num?)?.toInt() ?? existing.sortOrder,
      positionX:
          (changes['positionX'] as num?)?.toDouble() ?? existing.positionX,
      positionY:
          (changes['positionY'] as num?)?.toDouble() ?? existing.positionY,
      reminderAt: changes.containsKey('reminderAt')
          ? DateTime.tryParse(changes['reminderAt'] as String? ?? '')
          : existing.reminderAt,
      createdAt: existing.createdAt,
      updatedAt: DateTime.now(),
    );
    _notes![index] = note;
    await _persist();
    return note;
  }

  @override
  Future<List<Note>> reorderNotes(
    String boardId,
    List<String> orderedIds,
  ) async {
    await _ensureLoaded();
    final boardNotes = _notes!
        .where((note) => note.boardId == boardId)
        .toList();
    final existingIds = boardNotes.map((note) => note.id).toSet();
    if (orderedIds.length != boardNotes.length ||
        orderedIds.toSet().length != orderedIds.length ||
        !existingIds.containsAll(orderedIds)) {
      throw const NotesPersistenceFailure();
    }

    final orderById = {
      for (var index = 0; index < orderedIds.length; index++)
        orderedIds[index]: index,
    };
    final now = DateTime.now();
    for (var index = 0; index < _notes!.length; index++) {
      final note = _notes![index];
      final sortOrder = orderById[note.id];
      if (sortOrder != null) {
        _notes![index] = note.copyWith(sortOrder: sortOrder, updatedAt: now);
      }
    }
    await _persist();
    return fetchNotes(boardId);
  }

  @override
  Future<void> deleteNote(String id) async {
    await _ensureLoaded();
    final index = _notes!.indexWhere((note) => note.id == id);
    if (index == -1) throw const NotesPersistenceFailure();
    _notes!.removeAt(index);
    await _persist();
  }

  @override
  bool get isLocalDataActive => true;

  @override
  Future<LocalNotesSnapshot> readLocalData() async {
    await _ensureLoaded();
    return LocalNotesSnapshot(
      lists: List.unmodifiable(_lists!),
      notes: List.unmodifiable(_notes!),
    );
  }

  @override
  Future<void> clearLocalData() async {
    await _ensureLoaded();
    final previousLists = _lists;
    final previousNotes = _notes;
    final now = DateTime.now();
    _lists = [
      NoteList(id: 'home', name: 'Mis notas', createdAt: now, updatedAt: now),
    ];
    _notes = [];
    try {
      await _persist();
    } catch (_) {
      _lists = previousLists;
      _notes = previousNotes;
      rethrow;
    }
  }

  Future<void> _ensureLoaded() async {
    if (_lists != null && _notes != null) return;
    _preferences = await _preferencesLoader();
    final stored = _preferences!.getString(_storageKey);
    if (stored != null) {
      try {
        final json = jsonDecode(stored) as Map<String, dynamic>;
        _lists = (json['lists'] as List<dynamic>? ?? const [])
            .map(
              (item) =>
                  NoteList.fromJson(Map<String, dynamic>.from(item as Map)),
            )
            .toList();
        _notes = (json['notes'] as List<dynamic>? ?? const [])
            .map(
              (item) => Note.fromJson(Map<String, dynamic>.from(item as Map)),
            )
            .toList();
      } on Object {
        _lists = null;
        _notes = null;
      }
    }

    if (_lists == null || _lists!.isEmpty || _notes == null) {
      final now = DateTime.now();
      _lists = [
        NoteList(id: 'home', name: 'Mis notas', createdAt: now, updatedAt: now),
      ];
      _notes = [];
      await _persist();
    }
  }

  Future<void> _persist() async {
    final didSave = await _preferences!.setString(
      _storageKey,
      jsonEncode({
        'lists': _lists!.map((list) => list.toJson()).toList(),
        'notes': _notes!.map((note) => note.toJson()).toList(),
      }),
    );
    if (!didSave) throw const NotesPersistenceFailure();
  }

  @override
  void dispose() {
    unawaited(_events.close());
  }
}
