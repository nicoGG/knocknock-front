import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/data/local_notes_repository.dart';
import 'package:nocknock/features/notes/data/notes_repository.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/logic/notes_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'pins notes first and persists drag ordering within each section',
    () async {
      final repository = LocalNotesRepository();
      final first = await repository.createNote(
        'home',
        const NoteDraft(
          title: 'Primera',
          content: '',
          color: NoteColor.yellow,
          authorName: 'Invitado',
        ),
      );
      final second = await repository.createNote(
        'home',
        const NoteDraft(
          title: 'Segunda',
          content: '',
          color: NoteColor.blue,
          authorName: 'Invitado',
        ),
      );
      final third = await repository.createNote(
        'home',
        const NoteDraft(
          title: 'Tercera',
          content: '',
          color: NoteColor.green,
          authorName: 'Invitado',
        ),
      );
      final cubit = NotesCubit(repository);
      await cubit.load();

      await cubit.togglePin(first);
      expect(cubit.state.notes.first.id, first.id);
      expect(cubit.state.notes.first.isPinned, isTrue);

      await cubit.reorderVisibleNotes([first.id, second.id, third.id]);
      expect(cubit.state.notes.map((note) => note.id), [
        first.id,
        second.id,
        third.id,
      ]);
      expect((await repository.fetchNotes('home')).map((note) => note.id), [
        first.id,
        second.id,
        third.id,
      ]);

      await cubit.close();
    },
  );

  test('applies list appearance changes received in real time', () async {
    final repository = _RealtimeLocalNotesRepository();
    final cubit = NotesCubit(repository);
    await cubit.load();

    const appearance = ListAppearance(
      backgroundPreset: ListBackgroundPreset.lavender,
      backgroundBlur: 6,
    );
    repository.emit(
      ListAppearanceChanged(cubit.state.selectedListId, appearance),
    );

    expect(cubit.state.selectedList?.appearance, appearance);

    await cubit.close();
  });

  test('applies list name changes received in real time', () async {
    final repository = _RealtimeLocalNotesRepository();
    final cubit = NotesCubit(repository);
    await cubit.load();
    final updatedAt = DateTime.utc(2026, 8, 12, 12, 30);

    repository.emit(
      ListNameChanged(cubit.state.selectedListId, 'Me deben', updatedAt),
    );

    expect(cubit.state.selectedList?.name, 'Me deben');
    expect(cubit.state.selectedList?.updatedAt, updatedAt);

    await cubit.close();
  });

  test(
    'loads, saves, and receives account board backgrounds in real time',
    () async {
      final repository = _RealtimeLocalNotesRepository();
      const pinnedAppearance = ListAppearance(
        backgroundPreset: ListBackgroundPreset.lavender,
        backgroundBlur: 3,
      );
      await repository.updateAggregateBoardAppearance(
        AggregateBoardScope.pinned,
        pinnedAppearance,
      );
      final cubit = NotesCubit(repository);

      await cubit.load();
      expect(cubit.state.aggregateBoardAppearances.pinned, pinnedAppearance);

      const reminderAppearance = ListAppearance(
        backgroundPreset: ListBackgroundPreset.ocean,
        backgroundBlur: 6,
      );
      await expectLater(
        cubit.updateAggregateBoardAppearance(
          AggregateBoardScope.withReminder,
          reminderAppearance,
        ),
        completion(isTrue),
      );
      expect(
        (await repository.fetchAggregateBoardAppearances()).withReminder,
        reminderAppearance,
      );

      const assignedAppearance = ListAppearance(
        backgroundPreset: ListBackgroundPreset.aurora,
      );
      repository.emit(
        const AggregateBoardAppearanceChanged(
          AggregateBoardScope.assignedToMe,
          assignedAppearance,
        ),
      );
      expect(
        cubit.state.aggregateBoardAppearances.assignedToMe,
        assignedAppearance,
      );

      await cubit.close();
    },
  );

  test('refreshes when a list key envelope becomes available', () async {
    final repository = _RealtimeLocalNotesRepository();
    final cubit = NotesCubit(repository);
    await cubit.load();

    expect(repository.fetchListsCalls, 1);
    repository.emit(ListKeyEnvelopeUpdated(cubit.state.selectedListId));
    await pumpEventQueue(times: 10);

    expect(repository.fetchListsCalls, 2);

    await cubit.close();
  });

  test('loads a large board progressively without duplicating notes', () async {
    final repository = _PaginatedLocalNotesRepository(65);
    final cubit = NotesCubit(repository);

    await cubit.load();

    expect(cubit.state.notes, hasLength(40));
    expect(cubit.state.hasMoreNotes, isTrue);
    expect(cubit.state.nextNotesCursor, 'page-2');

    await cubit.loadMoreNotes();

    expect(cubit.state.notes, hasLength(65));
    expect(cubit.state.notes.map((note) => note.id).toSet(), hasLength(65));
    expect(cubit.state.hasMoreNotes, isFalse);
    expect(cubit.state.nextNotesCursor, isNull);
    expect(repository.pageRequests, [null, 'page-2']);
    await cubit.close();
  });
}

class _PaginatedLocalNotesRepository extends LocalNotesRepository
    implements PaginatedNotesRepository {
  _PaginatedLocalNotesRepository(int count)
    : notes = [
        for (var index = 0; index < count; index++)
          Note(
            id: 'note-${index.toString().padLeft(3, '0')}',
            boardId: 'home',
            title: 'Nota $index',
            content: '',
            color: NoteColor.yellow,
            authorName: 'Invitado',
            isCompleted: false,
            sortOrder: index,
            positionX: 0,
            positionY: 0,
            createdAt: DateTime.utc(2026, 8, 12),
            updatedAt: DateTime.utc(2026, 8, 12),
          ),
      ];

  final List<Note> notes;
  final pageRequests = <String?>[];

  @override
  Future<NotesPage> fetchNotesPage(
    String boardId, {
    String? cursor,
    int limit = 40,
  }) async {
    pageRequests.add(cursor);
    final start = cursor == null ? 0 : limit;
    final end = (start + limit).clamp(0, notes.length);
    return NotesPage(
      items: notes.sublist(start, end),
      nextCursor: end < notes.length ? 'page-2' : null,
    );
  }
}

class _RealtimeLocalNotesRepository extends LocalNotesRepository {
  final _realtimeEvents = StreamController<NotesRealtimeEvent>.broadcast(
    sync: true,
  );

  @override
  Stream<NotesRealtimeEvent> get realtimeEvents => _realtimeEvents.stream;

  int fetchListsCalls = 0;

  @override
  Future<List<NoteList>> fetchLists() {
    fetchListsCalls++;
    return super.fetchLists();
  }

  void emit(NotesRealtimeEvent event) => _realtimeEvents.add(event);

  @override
  void dispose() {
    super.dispose();
    unawaited(_realtimeEvents.close());
  }
}
