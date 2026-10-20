import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/data/local_notes_repository.dart';
import 'package:nocknock/features/notes/data/notes_repository.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/logic/notes_state.dart';
import 'package:nocknock/features/notes/data/selected_list_store.dart';
import 'package:nocknock/features/notes/logic/notes_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'switches to cached notes immediately and decodes cache only once',
    () async {
      final repository = _SwitchRepository();
      final list = await repository.createList('Viaje');
      final note = await repository.createNote(
        list.id,
        const NoteDraft(
          title: 'Pasajes',
          content: '',
          color: NoteColor.yellow,
          authorName: 'Invitado',
        ),
      );
      final cubit = NotesCubit(repository);
      await cubit.load();
      final delayed = Completer<List<Note>>();
      repository.delayedNotes = delayed;
      final switching = cubit.selectList(list.id);

      expect(cubit.state.status, NotesStatus.ready);
      expect(cubit.state.notes.map((item) => item.id), [note.id]);
      expect(repository.cacheReads, 1);

      // A late response from the first selection must not replace the new list.
      repository.delayedNotes = null;
      await cubit.selectList('home');
      delayed.complete([]);
      await switching;
      expect(cubit.state.selectedListId, 'home');
      expect(repository.cacheReads, 1);
      await cubit.close();
    },
  );

  test(
    'keeps session edits visible when returning during a slow refresh',
    () async {
      final repository = _SwitchRepository();
      final list = await repository.createList('Viaje');
      final cubit = NotesCubit(repository);
      await cubit.load();
      await cubit.createNote(
        const NoteDraft(
          title: 'Nueva',
          content: '',
          color: NoteColor.yellow,
          authorName: 'Invitado',
        ),
      );
      final note = cubit.state.notes.single;
      await cubit.selectList(list.id);
      final delayed = Completer<List<Note>>();
      repository.delayedNotes = delayed;
      final switching = cubit.selectList('home');
      expect(cubit.state.status, NotesStatus.ready);
      expect(cubit.state.notes.map((item) => item.id), [note.id]);
      delayed.completeError(const NotesPersistenceFailure());
      await switching;
      expect(cubit.state.status, NotesStatus.ready);
      expect(cubit.state.notes.map((item) => item.id), [note.id]);
      await cubit.close();
    },
  );

  test('restores the last selected list after reopening the app', () async {
    final firstRepository = LocalNotesRepository();
    final selectedList = await firstRepository.createList('Viaje');
    final firstCubit = NotesCubit(firstRepository);

    await firstCubit.load();
    await firstCubit.selectList(selectedList.id);
    expect(firstCubit.state.selectedListId, selectedList.id);
    await firstCubit.close();

    final reopenedCubit = NotesCubit(LocalNotesRepository());
    await reopenedCubit.load();

    expect(reopenedCubit.state.selectedListId, selectedList.id);
    expect(reopenedCubit.state.selectedList?.name, 'Viaje');
    await reopenedCubit.close();
  });

  test('falls back safely when the remembered list no longer exists', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      SharedPreferencesSelectedListStore.storageKey,
      'deleted-list',
    );
    final cubit = NotesCubit(LocalNotesRepository());

    await cubit.load();

    expect(cubit.state.selectedListId, 'home');
    expect(
      preferences.getString(SharedPreferencesSelectedListStore.storageKey),
      'home',
    );
    await cubit.close();
  });
}

class _SwitchRepository extends LocalNotesRepository
    implements NotesCacheReader {
  int cacheReads = 0;
  Completer<List<Note>>? delayedNotes;

  @override
  Future<List<Note>> fetchNotes(String boardId) =>
      delayedNotes?.future ?? super.fetchNotes(boardId);

  @override
  Future<NotesCacheSnapshot?> readCache() async {
    cacheReads++;
    final lists = await fetchLists();
    return NotesCacheSnapshot(
      lists: lists,
      notesByBoard: {
        for (final list in lists) list.id: await super.fetchNotes(list.id),
      },
    );
  }
}
