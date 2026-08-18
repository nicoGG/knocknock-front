import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/data/local_notes_repository.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('guest changes remain available after reopening the repository', () async {
    final repository = LocalNotesRepository();
    final initialLists = await repository.fetchLists();

    expect(initialLists, hasLength(1));
    expect(initialLists.single.id, 'home');

    final list = await repository.createList('Trabajo');
    final note = await repository.createNote(
      list.id,
      const NoteDraft(
        title: 'Preparar reunión',
        content: 'Revisar los pendientes',
        contentDelta:
            '[{"insert":"Revisar","attributes":{"bold":true}},{"insert":" los pendientes\\n"}]',
        color: NoteColor.blue,
        category: NoteCategory.work,
        checklist: [
          NoteChecklistItem(id: 'task-1', text: 'Enviar la pauta'),
          NoteChecklistItem(
            id: 'task-2',
            text: 'Confirmar asistentes',
            indent: 1,
          ),
        ],
        authorName: 'Invitado',
        assigneeUid: 'local-user',
      ),
    );
    await repository.updateNote(note.id, {
      'title': 'Preparar reunión semanal',
      'isCompleted': true,
    });
    repository.dispose();

    final reopenedRepository = LocalNotesRepository();
    final storedLists = await reopenedRepository.fetchLists();
    final storedNotes = await reopenedRepository.fetchNotes(list.id);

    expect(storedLists.map((item) => item.name), contains('Trabajo'));
    expect(storedNotes, hasLength(1));
    expect(storedNotes.single.title, 'Preparar reunión semanal');
    expect(storedNotes.single.isCompleted, isTrue);
    expect(storedNotes.single.contentDelta, contains('"bold":true'));
    expect(storedNotes.single.category, NoteCategory.work);
    expect(storedNotes.single.checklist.map((item) => item.text), [
      'Enviar la pauta',
      'Confirmar asistentes',
    ]);
    expect(storedNotes.single.checklist.last.indent, 1);
    expect(storedNotes.single.assigneeUid, 'local-user');

    await reopenedRepository.deleteNote(note.id);
    expect(await reopenedRepository.fetchNotes(list.id), isEmpty);
    reopenedRepository.dispose();

    final afterDeletionRepository = LocalNotesRepository();
    expect(await afterDeletionRepository.fetchNotes(list.id), isEmpty);
    afterDeletionRepository.dispose();
  });

  test('clears every guest list and note from local storage', () async {
    final repository = LocalNotesRepository();
    final list = await repository.createList('Personal');
    await repository.createNote(
      list.id,
      const NoteDraft(
        title: 'Dato local',
        content: 'Solo vive en este dispositivo',
        color: NoteColor.green,
        authorName: 'Invitado',
      ),
    );

    await repository.clearLocalData();

    final lists = await repository.fetchLists();
    expect(lists, hasLength(1));
    expect(lists.single.id, 'home');
    expect(await repository.fetchNotes(list.id), isEmpty);
    repository.dispose();

    final reopenedRepository = LocalNotesRepository();
    expect(await reopenedRepository.fetchLists(), hasLength(1));
    expect(await reopenedRepository.fetchNotes(list.id), isEmpty);
    reopenedRepository.dispose();
  });

  test('keeps deleted guest notes in trash and restores them', () async {
    final repository = LocalNotesRepository();
    final note = await repository.createNote(
      'home',
      const NoteDraft(
        title: 'Recuperar esta nota',
        content: '',
        color: NoteColor.yellow,
        authorName: 'Invitado',
      ),
    );

    await repository.deleteNote(note.id);

    expect(await repository.fetchNotes('home'), isEmpty);
    final trash = await repository.fetchTrash();
    expect(trash, hasLength(1));
    expect(trash.single.deletedAt, isNotNull);

    final restored = await repository.restoreNote(note.id);
    expect(restored.deletedAt, isNull);
    expect(await repository.fetchTrash(), isEmpty);
    expect(await repository.fetchNotes('home'), [restored]);
    repository.dispose();
  });

  test(
    'permanently deletes one trashed note and can empty the trash',
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
      await repository.deleteNote(first.id);
      await repository.deleteNote(second.id);

      await repository.permanentlyDeleteNote(first.id);
      expect((await repository.fetchTrash()).single.id, second.id);

      expect(await repository.emptyTrash(), 1);
      expect(await repository.fetchTrash(), isEmpty);
      repository.dispose();
    },
  );

  test('renames a guest list and deletes it with its notes', () async {
    final repository = LocalNotesRepository();
    final list = await repository.createList('Trabajo');
    await repository.createNote(
      list.id,
      const NoteDraft(
        title: 'Pendiente',
        content: '',
        color: NoteColor.yellow,
        authorName: 'Invitado',
      ),
    );

    final renamed = await repository.updateList(list.id, 'Proyectos');
    expect(renamed.name, 'Proyectos');
    await repository.deleteList(list.id);
    repository.dispose();

    final reopenedRepository = LocalNotesRepository();
    expect(
      (await reopenedRepository.fetchLists()).map((item) => item.name),
      isNot(contains('Proyectos')),
    );
    expect(await reopenedRepository.fetchNotes(list.id), isEmpty);
    reopenedRepository.dispose();
  });

  test('allows deleting the initial guest list', () async {
    final repository = LocalNotesRepository();
    final initial = (await repository.fetchLists()).single;

    await repository.deleteList(initial.id);

    expect(await repository.fetchLists(), isEmpty);
    repository.dispose();
  });

  test('persists the background appearance for each guest list', () async {
    final repository = LocalNotesRepository();
    final list = (await repository.fetchLists()).single;
    const appearance = ListAppearance(
      backgroundPreset: ListBackgroundPreset.lavender,
      backgroundBlur: 7,
    );

    await repository.updateListAppearance(list.id, appearance);
    final reopenedRepository = LocalNotesRepository();
    final reopenedList = (await reopenedRepository.fetchLists()).single;

    expect(reopenedList.appearance, appearance);
  });

  test('persists the custom order of guest lists', () async {
    final repository = LocalNotesRepository();
    final home = (await repository.fetchLists()).single;
    final work = await repository.createList('Trabajo');

    await repository.reorderLists([work.id, home.id]);
    repository.dispose();

    final reopened = LocalNotesRepository();
    expect((await reopened.fetchLists()).map((list) => list.id), [
      work.id,
      home.id,
    ]);
    reopened.dispose();
  });

  test('persists pinned notes and their manual order', () async {
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
    await repository.updateNote(first.id, {'isPinned': true, 'sortOrder': 0});
    await repository.reorderNotes('home', [first.id, second.id]);
    repository.dispose();

    final reopened = LocalNotesRepository();
    final notes = await reopened.fetchNotes('home');
    final pinnedNotes = await reopened.fetchPinnedNotes();
    expect(notes.map((note) => note.id), [first.id, second.id]);
    expect(notes.first.isPinned, isTrue);
    expect(pinnedNotes.map((note) => note.id), [first.id]);
    expect(notes.map((note) => note.sortOrder), [0, 1]);
    reopened.dispose();
  });

  test('persists aggregate board backgrounds on this device', () async {
    final repository = LocalNotesRepository();
    const appearance = ListAppearance(
      backgroundPreset: ListBackgroundPreset.sage,
      backgroundBlur: 5,
    );

    await repository.updateAggregateBoardAppearance(
      AggregateBoardScope.withReminder,
      appearance,
    );
    repository.dispose();

    final reopened = LocalNotesRepository();
    final appearances = await reopened.fetchAggregateBoardAppearances();

    expect(appearances.withReminder, appearance);
    expect(appearances.assignedToMe, const ListAppearance());
    expect(appearances.pinned, const ListAppearance());
    reopened.dispose();
  });

  test('lists notes with reminders ordered by reminder date', () async {
    final repository = LocalNotesRepository();
    final later = await repository.createNote(
      'home',
      NoteDraft(
        title: 'Más tarde',
        content: '',
        color: NoteColor.yellow,
        authorName: 'Invitado',
        reminderAt: DateTime(2026, 8, 20, 9),
      ),
    );
    final sooner = await repository.createNote(
      'home',
      NoteDraft(
        title: 'Primero',
        content: '',
        color: NoteColor.blue,
        authorName: 'Invitado',
        reminderAt: DateTime(2026, 8, 12, 9),
      ),
    );
    await repository.createNote(
      'home',
      const NoteDraft(
        title: 'Sin recordatorio',
        content: '',
        color: NoteColor.green,
        authorName: 'Invitado',
      ),
    );

    final reminders = await repository.fetchReminderNotes();

    expect(reminders.map((note) => note.id), [sooner.id, later.id]);
    repository.dispose();
  });

  test('persists idempotent emoji reactions for guest notes', () async {
    final repository = LocalNotesRepository();
    final note = await repository.createNote(
      'home',
      const NoteDraft(
        title: 'Celebrar avance',
        content: '',
        color: NoteColor.yellow,
        authorName: 'Invitado',
      ),
    );

    await repository.setNoteReaction(note.id, '🎉', true);
    await repository.setNoteReaction(note.id, '🎉', true);
    await repository.setNoteReaction(note.id, '👍', true);
    await repository.setNoteReaction(note.id, '🔥', true);
    repository.dispose();

    final reopened = LocalNotesRepository();
    var stored = (await reopened.fetchNotes('home')).single;
    expect(stored.reactions.map((reaction) => reaction.emoji), [
      '👍',
      '🎉',
      '🔥',
    ]);
    expect(stored.reactions.every((reaction) => reaction.count == 1), isTrue);
    expect(
      stored.reactions.every(
        (reaction) => reaction.isSelectedBy(localNoteReactionUserId),
      ),
      isTrue,
    );

    await reopened.setNoteReaction(note.id, '🎉', false);
    stored = (await reopened.fetchNotes('home')).single;
    expect(stored.reactions.map((reaction) => reaction.emoji), ['👍', '🔥']);
    reopened.dispose();
  });
}
