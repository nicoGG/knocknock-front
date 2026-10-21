import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nocknock/features/notes/data/local_notes_repository.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/logic/notes_cubit.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_history_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async => initializeDateFormatting('es'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<Note> create(LocalNotesRepository repository) => repository.createNote(
    'home',
    const NoteDraft(
      title: 'Versión original',
      content: 'Texto original',
      color: NoteColor.blue,
      authorName: 'Nico',
    ),
  );

  test('history persists, stays bounded, excludes position changes and is deleted with notes', () async {
    final repository = LocalNotesRepository();
    final note = await create(repository);
    await repository.updateNote(note.id, {'positionX': 40});
    expect(await repository.fetchNoteHistory(note.id), isEmpty);
    for (var i = 0; i < 12; i++) {
      await repository.updateNote(note.id, {'title': 'Edición $i'});
    }
    final reopened = LocalNotesRepository();
    final history = await reopened.fetchNoteHistory(note.id);
    expect(history.length, 10);
    expect(history.first.note.title, 'Edición 10');
    expect(history.last.note.title, 'Edición 1');
    await reopened.deleteNote(note.id);
    await reopened.permanentlyDeleteNote(note.id);
    await expectLater(
      reopened.fetchNoteHistory(note.id),
      throwsA(isA<Exception>()),
    );
    repository.dispose();
    reopened.dispose();
  });

  test('restoring content keeps current scheduling, assignment, status and permits undo through history', () async {
    final repository = LocalNotesRepository();
    final original = await create(repository);
    final reminder = DateTime(2027, 1, 2, 12);
    await repository.updateNote(original.id, {
      'title': 'Nuevo texto',
      'assigneeUids': ['ana'],
      'reminderAt': reminder.toIso8601String(),
      'isCompleted': true,
    });
    final cubit = NotesCubit(repository);
    final current = (await repository.fetchNotes('home')).single;
    final version = (await cubit.loadNoteHistory(original.id)).single;
    await cubit.restoreNoteVersion(current, version);
    final restored = (await repository.fetchNotes('home')).single;
    expect(restored.title, original.title);
    expect(restored.assignedUserIds, ['ana']);
    expect(restored.reminderAt, reminder);
    expect(restored.isCompleted, isTrue);
    expect(
      (await repository.fetchNoteHistory(original.id)).first.note.title,
      'Nuevo texto',
    );
    await expectLater(
      cubit.restoreNoteVersion(current, version),
      throwsA(isA<Exception>()),
    );
    await cubit.close();
    repository.dispose();
  });

  testWidgets(
    'history previews the version and requires confirmation before restoring',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = LocalNotesRepository();
      final original = (await tester.runAsync(() => create(repository)))!;
      await tester.runAsync(
        () => repository.updateNote(original.id, {'title': 'Actual'}),
      );
      var current = (await tester.runAsync(
        () => repository.fetchNotes('home'),
      ))!.single;
      final guard = ValueNotifier(true);
      var restorations = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Historial'),
                onPressed: () => showNoteHistorySheet(
                  context: context,
                  currentNote: () => current,
                  load: () => repository.fetchNoteHistory(original.id),
                  protectionChanges: guard,
                  canAccess: () => guard.value,
                  restore: (note, version) async {
                    restorations++;
                    current = await repository.restoreNoteContent(note.id, {
                      'expectedRevision': note.revision,
                      'title': version.note.title,
                    });
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Historial'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Editó Nico'), findsOneWidget);
      await tester.tap(
        find.byKey(ValueKey('note-version-${original.revision}')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Versión original'), findsOneWidget);
      await tester.tap(
        find.byKey(ValueKey('restore-version-${original.revision}')),
      );
      await tester.pumpAndSettle();
      expect(restorations, 0);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(restorations, 0);
      guard.value = false;
      await tester.pumpAndSettle();
      expect(find.text('Versión original'), findsNothing);
      expect(
        find.text('Desbloquea la lista para ver el historial.'),
        findsOneWidget,
      );
      guard.value = true;
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('note-version-${original.revision}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('restore-version-${original.revision}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-restore-version')));
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(restorations, 1);
      expect(current.title, 'Versión original');
      await tester.pumpWidget(const SizedBox());
      guard.dispose();
      repository.dispose();
    },
  );
}
