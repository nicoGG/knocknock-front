import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/data/cached_notes_repository.dart';
import 'package:nocknock/features/notes/data/notes_repository.dart';
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

Note _note({required String title}) {
  final date = DateTime.utc(2026, 8, 10, 12);
  return Note(
    id: 'note-1',
    boardId: 'list-1',
    title: title,
    content: '',
    color: NoteColor.yellow,
    authorName: 'Nico',
    isCompleted: false,
    positionX: 0,
    positionY: 0,
    createdAt: date,
    updatedAt: date,
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
  final List<Note> notes;
  AggregateBoardAppearances aggregateBoardAppearances;

  @override
  Stream<NotesRealtimeEvent> get realtimeEvents => const Stream.empty();

  @override
  Future<List<NoteList>> fetchLists() async => lists;

  @override
  Future<List<Note>> fetchNotes(String boardId) async => notes;

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
