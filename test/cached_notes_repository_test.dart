import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/data/cached_notes_repository.dart';
import 'package:nocknock/features/notes/data/notes_repository.dart';
import 'package:nocknock/features/notes/data/offline_mutation_store.dart';
import 'package:nocknock/features/notes/data/selected_list_store.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/logic/notes_cubit.dart';
import 'package:nocknock/features/notes/logic/notes_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('persists a complete snapshot and isolates it by account', () async {
    var currentUserId = 'user-1';
    final preferences = await SharedPreferences.getInstance();
    final list = _list();
    final note = _note(title: 'Guardada');
    final repository = CachedNotesRepository(
      repository: _FakeRemoteRepository(
        lists: [list],
        notes: [note],
        aggregateBoardAppearances: const AggregateBoardAppearances(
          pinned: ListAppearance(
            backgroundPreset: ListBackgroundPreset.lavender,
          ),
        ),
      ),
      preferences: preferences,
      userIdProvider: () => currentUserId,
    );

    await repository.fetchLists();
    await repository.fetchNotes(list.id);
    await repository.fetchAggregateBoardAppearances();
    await pumpEventQueue();
    repository.dispose();

    final reopenedRepository = CachedNotesRepository(
      repository: _FakeRemoteRepository(lists: const [], notes: const []),
      preferences: preferences,
      userIdProvider: () => currentUserId,
    );

    final cached = await reopenedRepository.readCache();
    expect(cached?.lists.single.collaborators.single.displayName, 'Nico');
    expect(cached?.lists.single.pendingInvitations.single.email, 'ana@test.cl');
    expect(cached?.notesByBoard[list.id]?.single.title, 'Guardada');
    expect(
      cached?.aggregateBoardAppearances?.pinned.backgroundPreset,
      ListBackgroundPreset.lavender,
    );

    currentUserId = 'user-2';
    expect(await reopenedRepository.readCache(), isNull);
    reopenedRepository.dispose();
  });

  test('shows cached notes before replacing them with fresh data', () async {
    final listsCompleter = Completer<List<NoteList>>();
    final notesCompleter = Completer<List<Note>>();
    final list = _list();
    final repository = _DelayedCachedRepository(
      snapshot: NotesCacheSnapshot(
        lists: [list],
        notesByBoard: {
          list.id: [_note(title: 'En caché')],
        },
      ),
      listsCompleter: listsCompleter,
      notesCompleter: notesCompleter,
    );
    final cubit = NotesCubit(
      repository,
      selectedListStore: _MemorySelectedListStore(list.id),
    );

    final load = cubit.load();
    await pumpEventQueue();

    expect(cubit.state.status, NotesStatus.ready);
    expect(cubit.state.notes.single.title, 'En caché');

    listsCompleter.complete([list]);
    await pumpEventQueue();
    notesCompleter.complete([_note(title: 'Actualizada')]);
    await load;

    expect(cubit.state.status, NotesStatus.ready);
    expect(cubit.state.notes.single.title, 'Actualizada');
    await cubit.close();
  });

  test(
    'queues an edit offline and sends it once connectivity returns',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final store = InMemoryOfflineMutationStore();
      final remote = _FakeRemoteRepository(
        lists: [_list()],
        notes: [_note(title: 'Original', revision: 4)],
      );
      final repository = CachedNotesRepository(
        repository: remote,
        preferences: preferences,
        userIdProvider: () => 'user-1',
        mutationStore: store,
      );
      await repository.fetchLists();
      await repository.fetchNotes('list-1');
      remote.isOffline = true;

      final local = await repository.updateNote('note-1', {
        'title': 'Cambio sin conexión',
      });

      expect(local.title, 'Cambio sin conexión');
      expect((await repository.offlineSyncSummary()).pendingCount, 1);
      expect(remote.notes.single.title, 'Original');

      remote.isOffline = false;
      await repository.syncPendingChanges();

      expect((await repository.offlineSyncSummary()).pendingCount, 0);
      expect(remote.notes.single.title, 'Cambio sin conexión');
      expect(remote.notes.single.revision, 5);
      repository.dispose();
    },
  );

  test('keeps both versions when an offline edit conflicts', () async {
    final preferences = await SharedPreferences.getInstance();
    final remote = _FakeRemoteRepository(
      lists: [_list()],
      notes: [_note(title: 'Base', revision: 2)],
    );
    final repository = CachedNotesRepository(
      repository: remote,
      preferences: preferences,
      userIdProvider: () => 'user-1',
      mutationStore: InMemoryOfflineMutationStore(),
    );
    await repository.fetchLists();
    await repository.fetchNotes('list-1');
    remote.notes = [_note(title: 'Cambio remoto', revision: 3)];

    final local = await repository.updateNote('note-1', {'title': 'Mi cambio'});
    final conflicts = await repository.fetchNoteSyncConflicts();

    expect(local.title, 'Mi cambio');
    expect(conflicts, hasLength(1));
    expect(conflicts.single.localNote.title, 'Mi cambio');
    expect(conflicts.single.remoteNote.title, 'Cambio remoto');

    await repository.resolveNoteSyncConflict(
      conflicts.single.mutationId,
      NoteConflictResolution.keepLocal,
    );

    expect(remote.notes.single.title, 'Mi cambio');
    expect(remote.notes.single.revision, 4);
    expect((await repository.offlineSyncSummary()).conflictCount, 0);
    repository.dispose();
  });

  test('queues a reaction offline and applies it after reconnecting', () async {
    final preferences = await SharedPreferences.getInstance();
    final remote = _FakeRemoteRepository(
      lists: [_list()],
      notes: [_note(title: 'Compartida', revision: 2)],
    );
    final repository = CachedNotesRepository(
      repository: remote,
      preferences: preferences,
      userIdProvider: () => 'user-1',
      mutationStore: InMemoryOfflineMutationStore(),
    );
    await repository.fetchLists();
    await repository.fetchNotes('list-1');
    remote.isOffline = true;

    final local = await repository.setNoteReaction('note-1', '🎉', true);

    expect(local.reactions.single.userUids, ['user-1']);
    expect(remote.notes.single.reactions, isEmpty);
    expect((await repository.offlineSyncSummary()).pendingCount, 1);

    remote.isOffline = false;
    await repository.syncPendingChanges();

    expect(remote.notes.single.reactions.single.userUids, ['user-1']);
    expect((await repository.offlineSyncSummary()).pendingCount, 0);
    repository.dispose();
  });

  test('compacts repeated offline reaction intents', () async {
    final preferences = await SharedPreferences.getInstance();
    final remote = _FakeRemoteRepository(
      lists: [_list()],
      notes: [_note(title: 'Compartida')],
    );
    final repository = CachedNotesRepository(
      repository: remote,
      preferences: preferences,
      userIdProvider: () => 'user-1',
      mutationStore: InMemoryOfflineMutationStore(),
    );
    await repository.fetchLists();
    await repository.fetchNotes('list-1');
    remote.isOffline = true;

    await repository.setNoteReaction('note-1', '👍', true);
    await repository.setNoteReaction('note-1', '👍', false);

    expect((await repository.offlineSyncSummary()).pendingCount, 1);
    remote.isOffline = false;
    await repository.syncPendingChanges();
    expect(remote.notes.single.reactions, isEmpty);
    repository.dispose();
  });

  test('keeps only the latest offline board order', () async {
    final preferences = await SharedPreferences.getInstance();
    final remote = _FakeRemoteRepository(
      lists: [_list()],
      notes: [
        _note(id: 'note-1', title: 'Uno', sortOrder: 0),
        _note(id: 'note-2', title: 'Dos', sortOrder: 1),
        _note(id: 'note-3', title: 'Tres', sortOrder: 2),
      ],
    );
    final repository = CachedNotesRepository(
      repository: remote,
      preferences: preferences,
      userIdProvider: () => 'user-1',
      mutationStore: InMemoryOfflineMutationStore(),
    );
    await repository.fetchLists();
    await repository.fetchNotes('list-1');
    remote.isOffline = true;

    await repository.reorderNotes('list-1', ['note-3', 'note-1', 'note-2']);
    final latest = await repository.reorderNotes('list-1', [
      'note-2',
      'note-3',
      'note-1',
    ]);

    expect(latest.map((note) => note.id), ['note-2', 'note-3', 'note-1']);
    expect((await repository.offlineSyncSummary()).pendingCount, 1);

    remote.isOffline = false;
    await repository.syncPendingChanges();

    expect(remote.notes.map((note) => note.id), ['note-2', 'note-3', 'note-1']);
    expect((await repository.offlineSyncSummary()).pendingCount, 0);
    repository.dispose();
  });

  test('rebases an offline order when a collaborator adds a note', () async {
    final preferences = await SharedPreferences.getInstance();
    final remote = _FakeRemoteRepository(
      lists: [_list()],
      notes: [
        _note(id: 'note-1', title: 'Uno', sortOrder: 0),
        _note(id: 'note-2', title: 'Dos', sortOrder: 1),
      ],
    );
    final repository = CachedNotesRepository(
      repository: remote,
      preferences: preferences,
      userIdProvider: () => 'user-1',
      mutationStore: InMemoryOfflineMutationStore(),
    );
    await repository.fetchLists();
    await repository.fetchNotes('list-1');
    remote.isOffline = true;
    await repository.reorderNotes('list-1', ['note-2', 'note-1']);
    remote.notes = [
      ...remote.notes,
      _note(id: 'note-3', title: 'Tres', sortOrder: 2),
    ];

    remote.isOffline = false;
    await repository.syncPendingChanges();

    expect(remote.notes.map((note) => note.id), ['note-2', 'note-1', 'note-3']);
    expect((await repository.offlineSyncSummary()).pendingCount, 0);
    repository.dispose();
  });

  test('rebases an online order from a stale board snapshot', () async {
    final preferences = await SharedPreferences.getInstance();
    final remote = _FakeRemoteRepository(
      lists: [_list()],
      notes: [
        _note(id: 'note-1', title: 'Uno', sortOrder: 0),
        _note(id: 'note-2', title: 'Dos', sortOrder: 1),
      ],
    );
    final repository = CachedNotesRepository(
      repository: remote,
      preferences: preferences,
      userIdProvider: () => 'user-1',
      mutationStore: InMemoryOfflineMutationStore(),
    );
    await repository.fetchLists();
    await repository.fetchNotes('list-1');
    remote.notes = [
      ...remote.notes,
      _note(id: 'note-3', title: 'Tres', sortOrder: 2),
    ];

    final saved = await repository.reorderNotes('list-1', ['note-2', 'note-1']);

    expect(saved.map((note) => note.id), ['note-2', 'note-1', 'note-3']);
    expect((await repository.offlineSyncSummary()).pendingCount, 0);
    repository.dispose();
  });

  test(
    'replays an offline create before its reaction and merged edit',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final remote = _FakeRemoteRepository(lists: [_list()], notes: []);
      final repository = CachedNotesRepository(
        repository: remote,
        preferences: preferences,
        userIdProvider: () => 'user-1',
        mutationStore: InMemoryOfflineMutationStore(),
      );
      await repository.fetchLists();
      await repository.fetchNotes('list-1');
      remote.isOffline = true;

      final created = await repository.createNote(
        'list-1',
        const NoteDraft(
          title: 'Nueva',
          content: '',
          color: NoteColor.yellow,
          authorName: 'Nico',
        ),
      );
      await repository.setNoteReaction(created.id, '🔥', true);
      await repository.updateNote(created.id, {'title': 'Nueva editada'});

      expect((await repository.offlineSyncSummary()).pendingCount, 2);
      remote.isOffline = false;
      await repository.syncPendingChanges();

      expect(remote.notes.single.title, 'Nueva editada');
      expect(remote.notes.single.reactions.single.emoji, '🔥');
      expect((await repository.offlineSyncSummary()).pendingCount, 0);
      repository.dispose();
    },
  );
}

NoteList _list() {
  final date = DateTime.utc(2026, 8, 10, 12);
  return NoteList(
    id: 'list-1',
    name: 'Trabajo',
    createdAt: date,
    updatedAt: date,
    collaborators: [
      ListCollaborator(
        uid: 'user-1',
        email: 'nico@test.cl',
        displayName: 'Nico',
        role: ListMemberRole.owner,
        joinedAt: date,
      ),
    ],
    pendingInvitations: [
      ListPendingInvitation(email: 'ana@test.cl', invitedAt: date),
    ],
  );
}

Note _note({
  String id = 'note-1',
  required String title,
  int revision = 0,
  int sortOrder = 0,
  List<NoteReaction> reactions = const [],
}) {
  final date = DateTime.utc(2026, 8, 10, 12);
  return Note(
    id: id,
    boardId: 'list-1',
    title: title,
    content: '',
    color: NoteColor.yellow,
    authorName: 'Nico',
    isCompleted: false,
    sortOrder: sortOrder,
    reactions: reactions,
    positionX: 0,
    positionY: 0,
    createdAt: date,
    updatedAt: date,
    revision: revision,
  );
}

class _FakeRemoteRepository
    implements NotesRepository, AggregateBoardAppearancesRepository {
  _FakeRemoteRepository({
    required this.lists,
    required this.notes,
    this.aggregateBoardAppearances = const AggregateBoardAppearances(),
  });

  final List<NoteList> lists;
  List<Note> notes;
  AggregateBoardAppearances aggregateBoardAppearances;
  bool isOffline = false;

  @override
  Stream<NotesRealtimeEvent> get realtimeEvents => const Stream.empty();

  @override
  Future<List<NoteList>> fetchLists() async => lists;

  @override
  Future<List<Note>> fetchNotes(String boardId) async => notes;

  @override
  Future<Note> createNote(String boardId, NoteDraft draft) async {
    _throwIfOffline('/notes');
    final now = DateTime.now();
    final note = Note(
      id: draft.clientNoteId!,
      boardId: boardId,
      title: draft.title,
      content: draft.content,
      contentDelta: draft.contentDelta,
      color: draft.color,
      authorName: draft.authorName,
      assigneeUid: draft.assigneeUid,
      isCompleted: draft.isCompleted,
      isPinned: draft.isPinned,
      sortOrder: draft.sortOrder ?? -now.microsecondsSinceEpoch,
      category: draft.category,
      checklist: draft.checklist,
      positionX: draft.positionX,
      positionY: draft.positionY,
      reminderAt: draft.reminderAt,
      revision: 1,
      createdAt: now,
      updatedAt: now,
    );
    notes = [...notes, note]..sort(compareNotes);
    return note;
  }

  @override
  Future<Note> updateNote(String id, Map<String, dynamic> changes) async {
    if (isOffline) {
      throw DioException(
        requestOptions: RequestOptions(path: '/notes/$id'),
        type: DioExceptionType.connectionError,
      );
    }
    final current = notes.singleWhere((note) => note.id == id);
    final expected = (changes['expectedRevision'] as num?)?.toInt();
    if (expected != null && expected != current.revision) {
      throw DioException(
        requestOptions: RequestOptions(path: '/notes/$id'),
        response: Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/notes/$id'),
          statusCode: 409,
          data: {'current': current.toJson()},
        ),
        type: DioExceptionType.badResponse,
      );
    }
    final json = current.toJson()
      ..addAll(changes)
      ..remove('expectedRevision')
      ..remove('clientMutationId')
      ..['revision'] = current.revision + 1
      ..['updatedAt'] = DateTime.now().toIso8601String();
    final updated = Note.fromJson(json);
    notes = [
      for (final note in notes)
        if (note.id == id) updated else note,
    ];
    return updated;
  }

  @override
  Future<Note> setNoteReaction(String id, String emoji, bool active) async {
    _throwIfOffline('/notes/$id/reactions');
    final current = notes.singleWhere((note) => note.id == id);
    final reactions = List<NoteReaction>.of(current.reactions);
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
    final updated = current.copyWith(
      reactions: reactions,
      updatedAt: DateTime.now(),
    );
    notes = [
      for (final note in notes)
        if (note.id == id) updated else note,
    ];
    return updated;
  }

  @override
  Future<List<Note>> reorderNotes(
    String boardId,
    List<String> orderedIds,
  ) async {
    _throwIfOffline('/notes/reorder');
    final notesById = {for (final note in notes) note.id: note};
    if (orderedIds.length != notes.length ||
        orderedIds.any((id) => !notesById.containsKey(id))) {
      throw DioException(
        requestOptions: RequestOptions(path: '/notes/reorder'),
        response: Response<void>(
          requestOptions: RequestOptions(path: '/notes/reorder'),
          statusCode: 400,
        ),
        type: DioExceptionType.badResponse,
      );
    }
    notes = [
      for (final entry in orderedIds.indexed)
        notesById[entry.$2]!.copyWith(
          sortOrder: entry.$1,
          updatedAt: DateTime.now(),
        ),
    ]..sort(compareNotes);
    return notes;
  }

  void _throwIfOffline(String path) {
    if (!isOffline) return;
    throw DioException(
      requestOptions: RequestOptions(path: path),
      type: DioExceptionType.connectionError,
    );
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
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DelayedCachedRepository implements NotesRepository, NotesCacheReader {
  _DelayedCachedRepository({
    required this.snapshot,
    required this.listsCompleter,
    required this.notesCompleter,
  });

  final NotesCacheSnapshot snapshot;
  final Completer<List<NoteList>> listsCompleter;
  final Completer<List<Note>> notesCompleter;

  @override
  Stream<NotesRealtimeEvent> get realtimeEvents => const Stream.empty();

  @override
  Future<NotesCacheSnapshot?> readCache() async => snapshot;

  @override
  Future<List<NoteList>> fetchLists() => listsCompleter.future;

  @override
  Future<List<Note>> fetchNotes(String boardId) => notesCompleter.future;

  @override
  Future<void> connect(String boardId) async {}

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemorySelectedListStore implements SelectedListStore {
  _MemorySelectedListStore(this.value);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String listId) async => value = listId;
}
