import 'package:flutter/material.dart';
import 'package:nocknock/core/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nocknock/features/notes/data/list_protection_controller.dart';
import 'package:nocknock/features/notes/data/local_notes_repository.dart';
import 'package:nocknock/features/notes/data/notes_repository.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/logic/notes_cubit.dart';
import 'package:nocknock/features/notes/presentation/today_page.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_preview_dialog.dart';
import 'package:nocknock/features/notes/presentation/widgets/post_it_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));
  final now = DateTime(2026, 10, 20, 12);
  final list = NoteList(
    id: 'home',
    name: 'Casa',
    createdAt: now,
    updatedAt: now,
  );
  NoteSearchResult result(
    String id, {
    DateTime? reminder,
    bool assigned = false,
    bool completed = false,
    DateTime? completedAt,
    bool deleted = false,
  }) => NoteSearchResult(
    list: list,
    note: Note(
      id: id,
      boardId: list.id,
      title: id,
      content: '',
      color: NoteColor.yellow,
      authorName: 'Nico',
      isCompleted: completed,
      completedAt: completedAt,
      positionX: 0,
      positionY: 0,
      createdAt: now,
      updatedAt: now,
      reminderAt: reminder,
      assigneeUids: assigned ? ['me'] : [],
      deletedAt: deleted ? now : null,
    ),
  );

  test(
    'uses local calendar boundaries, excludes completed/deleted, deduplicates',
    () {
      final overdue = result(
        'overdue',
        reminder: DateTime(2026, 10, 19, 23, 59),
        assigned: true,
      );
      final groups = groupTodayNotes(
        [
          overdue,
          overdue,
          result('midnight', reminder: DateTime(2026, 10, 20)),
          result(
            'earlier',
            reminder: DateTime(2026, 10, 20, 8).toUtc(),
            assigned: true,
          ),
          result('late', reminder: DateTime(2026, 10, 20, 23, 59)),
          result('tomorrow', reminder: DateTime(2026, 10, 21)),
          result('mine', assigned: true),
          result(
            'future-mine',
            assigned: true,
            reminder: DateTime(2026, 10, 21),
          ),
          result('other'),
          result('done', assigned: true, completed: true),
          result(
            'done-reminder',
            reminder: DateTime(2026, 10, 21),
            completed: true,
          ),
          result(
            'deleted-reminder',
            reminder: DateTime(2026, 10, 21),
            deleted: true,
          ),
          result('deleted', assigned: true, deleted: true),
        ],
        now: now,
        userId: 'me',
      );
      expect(groups['Atrasadas']!.map((r) => r.note.id), ['overdue']);
      expect(groups['Para hoy']!.map((r) => r.note.id), [
        'midnight',
        'earlier',
        'late',
      ]);
      expect(groups['Asignadas a mí']!.map((r) => r.note.id), ['mine']);
      expect(groups['Próximos recordatorios']!.map((r) => r.note.id), [
        'future-mine',
        'tomorrow',
      ]);
      expect(
        groupTodayNotes(
          [
            result('later', reminder: DateTime(2026, 10, 23)),
            result('tomorrow', reminder: DateTime(2026, 10, 21)),
          ],
          now: now,
          userId: null,
        )['Próximos recordatorios']!.map((r) => r.note.id),
        ['tomorrow', 'later'],
      );
      expect(
        groupTodayNotes(
          [result('mine', assigned: true)],
          now: now,
          userId: null,
        ).values.expand((group) => group),
        isEmpty,
      );
    },
  );

  test(
    'postponement is available only for pending reminders on the local day',
    () {
      expect(
        canPostponeTodayReminder(
          result('today', reminder: now.toUtc()).note,
          now,
        ),
        isTrue,
      );
      expect(
        canPostponeTodayReminder(
          result('past-hour', reminder: DateTime(2026, 10, 20, 1)).note,
          now,
        ),
        isTrue,
      );
      expect(
        canPostponeTodayReminder(
          result('yesterday', reminder: DateTime(2026, 10, 19, 23, 59)).note,
          now,
        ),
        isFalse,
      );
      expect(
        canPostponeTodayReminder(
          result('tomorrow', reminder: DateTime(2026, 10, 21)).note,
          now,
        ),
        isFalse,
      );
      expect(
        canPostponeTodayReminder(
          result('done', reminder: now, completed: true).note,
          now,
        ),
        isFalse,
      );
      expect(
        canPostponeTodayReminder(result('no-reminder').note, now),
        isFalse,
      );
      expect(
        canPostponeTodayReminder(
          result('midnight', reminder: now).note,
          DateTime(2026, 10, 21),
        ),
        isFalse,
      );
    },
  );

  test('completed today uses completion time rather than the last edit', () {
    final done = result('today', completed: true, completedAt: now.toUtc());
    final groups = groupTodayNotes(
      [
        done,
        result('old', completed: true, completedAt: DateTime(2026, 10, 19)),
        result('unknown', completed: true),
        result('reopened', completedAt: now),
        result('deleted', completed: true, completedAt: now, deleted: true),
      ],
      now: now,
      userId: null,
    );
    expect(groups['Completadas hoy']!.map((r) => r.note.id), ['today']);
    expect(
      Note.fromJson(done.note.toJson()).completedAt!.toUtc(),
      done.note.completedAt!.toUtc(),
    );
    expect(
      done.note.copyWith(isPinned: true).completedAt,
      done.note.completedAt,
    );
  });

  test('upcoming groups respect local week boundaries including Sundays', () {
    final groups = groupUpcomingReminders([
      result('tomorrow', reminder: DateTime(2026, 10, 21)),
      result('sunday', reminder: DateTime(2026, 10, 25, 23, 59)),
      result('monday', reminder: DateTime(2026, 10, 26)),
    ], now: now);
    expect(groups['Mañana']!.map((r) => r.note.id), ['tomorrow']);
    expect(groups['Esta semana']!.map((r) => r.note.id), ['sunday']);
    expect(groups['Más adelante']!.map((r) => r.note.id), ['monday']);
    final sunday = groupUpcomingReminders([
      result('monday', reminder: DateTime(2026, 10, 26)),
      result('tuesday', reminder: DateTime(2026, 10, 27)),
    ], now: DateTime(2026, 10, 25));
    expect(sunday['Mañana']!.map((r) => r.note.id), ['monday']);
    expect(sunday['Esta semana'], isEmpty);
    expect(sunday['Más adelante']!.map((r) => r.note.id), ['tuesday']);
  });

  test(
    'completion persists through edits, reload and reopening a guest note',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repository = LocalNotesRepository();
      final note = await repository.createNote(
        'home',
        const NoteDraft(
          title: 'Tarea',
          content: '',
          color: NoteColor.blue,
          authorName: 'Nico',
        ),
      );
      final cubit = NotesCubit(repository);
      await cubit.load();
      final done = await cubit.completeTodayNote(note);
      expect(done.isCompleted, isTrue);
      expect(done.completedAt, isNotNull);
      await repository.updateNote(note.id, {'title': 'Título nuevo'});
      final reloaded = (await LocalNotesRepository().fetchNotes('home')).single;
      expect(reloaded.completedAt!.toUtc(), done.completedAt!.toUtc());
      final pending = await repository.updateNote(note.id, {
        'isCompleted': false,
      });
      expect(pending.completedAt, isNull);
      await cubit.close();
    },
  );

  testWidgets(
    'quick actions, filters, progress, upcoming expansion and creation persist',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _FailingTodayRepository();
      final today = DateTime.now();
      final notes = (await tester.runAsync(() async {
        final list = await repository.createList('Trabajo');
        final task = await repository.createNote(
          list.id,
          NoteDraft(
            title: 'Terminar tarea',
            content: '',
            authorName: 'Nico',
            color: NoteColor.blue,
            reminderAt: today,
          ),
        );
        final recurring = await repository.createNote(
          list.id,
          NoteDraft(
            title: 'Rutina diaria',
            content: '',
            authorName: 'Nico',
            color: NoteColor.yellow,
            reminderAt: today,
            reminderRecurrence: const ReminderRecurrence(
              frequency: ReminderRecurrenceFrequency.daily,
              interval: 1,
              timeZoneOffsetMinutes: 0,
            ),
          ),
        );
        final later = await repository.createNote(
          list.id,
          NoteDraft(
            title: 'Viaje futuro',
            content: '',
            authorName: 'Nico',
            color: NoteColor.pink,
            reminderAt: today.add(const Duration(days: 10)),
          ),
        );
        return [task, recurring, later];
      }))!;
      final cubit = NotesCubit(repository);
      await tester.runAsync(cubit.load);
      final protection = ListProtectionController();
      String? createdIn;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: TodayPage(
            cubit: cubit,
            protection: protection,
            userId: null,
            onPreviewNote: (_, _) async => false,
            onCreateNote: (context, id) async {
              createdIn = id;
              final draft = await showCreateNoteDialog(
                context: context,
                defaultAuthorName: 'Nico',
                showAuthorField: false,
                assignees: const [],
              );
              if (draft != null) await repository.createNote(id, draft);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('0 de 2 pendientes completados hoy'), findsOneWidget);
      expect(
        find.byKey(ValueKey('today-complete-${notes[1].id}')),
        findsNothing,
      );
      expect(find.text('Viaje futuro'), findsNothing);

      Future<void> reveal(Finder finder) async {
        await tester.drag(find.byType(ListView).first, const Offset(0, 2000));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          finder,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
      }

      final complete = find.byKey(ValueKey('today-complete-${notes[0].id}'));
      await reveal(complete);
      await tester.tap(complete);
      await tester.pumpAndSettle();
      expect(find.text('¿Completar esta nota?'), findsOneWidget);
      expect(
        (await repository.fetchNotes(notes[0].boardId))
            .firstWhere((n) => n.id == notes[0].id)
            .isCompleted,
        isFalse,
      );
      await tester.tap(
        find.byKey(const ValueKey('cancel-today-complete-button')),
      );
      await tester.pumpAndSettle();
      expect(
        (await repository.fetchNotes(notes[0].boardId))
            .firstWhere((n) => n.id == notes[0].id)
            .isCompleted,
        isFalse,
      );
      repository.failUpdates = true;
      await tester.tap(complete);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('confirm-today-complete-button')),
      );
      await tester.pumpAndSettle();
      expect(
        (await repository.fetchNotes(notes[0].boardId))
            .firstWhere((n) => n.id == notes[0].id)
            .isCompleted,
        isFalse,
      );
      expect(
        find.text('Ocurrió un problema inesperado. Inténtalo nuevamente.'),
        findsOneWidget,
      );
      repository.failUpdates = false;
      await tester.tap(complete);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('confirm-today-complete-button')),
      );
      await tester.pumpAndSettle();
      final saved = (await repository.fetchNotes(notes[0].boardId))
          .firstWhere((n) => n.id == notes[0].id);
      expect(saved.isCompleted, isTrue);
      expect(saved.completedAt, isNotNull);
      final undoBar = find.byKey(
        const ValueKey('today-completion-undo-snackbar'),
      );
      expect(undoBar, findsOneWidget);
      expect(tester.widget<SnackBar>(undoBar).behavior, SnackBarBehavior.fixed);
      expect(find.text('8 s'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('6 s'), findsOneWidget);
      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      final restored = (await repository.fetchNotes(notes[0].boardId))
          .firstWhere((n) => n.id == notes[0].id);
      expect(restored.isCompleted, isFalse);
      expect(restored.completedAt, isNull);
      expect(
        find.byKey(const ValueKey('today-filter-Completadas hoy')),
        findsNothing,
      );
      await reveal(complete);
      expect(find.text('0 de 2 pendientes completados hoy'), findsOneWidget);
      await tester.tap(complete);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('confirm-today-complete-button')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Deshacer'), findsOneWidget);
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();
      expect(find.text('Deshacer'), findsNothing);
      expect(
        (await repository.fetchNotes(notes[0].boardId))
            .firstWhere((n) => n.id == notes[0].id)
            .isCompleted,
        isTrue,
      );
      final completedFilter = find.byKey(
        const ValueKey('today-filter-Completadas hoy'),
      );
      await reveal(completedFilter);
      expect(find.text('1 de 2 pendientes completados hoy'), findsOneWidget);
      await tester.tap(completedFilter);
      await tester.pumpAndSettle();
      expect(find.text('Terminar tarea'), findsOneWidget);
      expect(find.text('Rutina diaria'), findsNothing);
      expect(find.text('Todo'), findsNothing);
      await tester.tap(completedFilter);
      await tester.pumpAndSettle();

      final postpone = find.byKey(ValueKey('today-postpone-${notes[1].id}'));
      expect(
        find.descendant(
          of: find.byKey(ValueKey('today-note-${notes[1].id}')),
          matching: postpone,
        ),
        findsOneWidget,
      );
      await reveal(postpone);
      await tester.tap(postpone);
      await tester.pumpAndSettle();
      await tester.tap(find.text('15 minutos'));
      await tester.pumpAndSettle();
      final postponed = (await repository.fetchNotes(notes[1].boardId))
          .firstWhere((n) => n.id == notes[1].id);
      expect(postponed.reminderAt!.isAfter(notes[1].reminderAt!), isTrue);
      expect(postponed.reminderRecurrence, notes[1].reminderRecurrence);

      await reveal(find.text('Más adelante · 1'));
      await tester.tap(find.text('Más adelante · 1'));
      await tester.pumpAndSettle();
      expect(find.text('Viaje futuro'), findsOneWidget);
      expect(
        find.byKey(ValueKey('today-postpone-${notes[2].id}')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('today-create-note-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trabajo'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('note-title-field')),
        'Nueva de Hoy',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-note-button')));
      await tester.pumpAndSettle();
      expect(createdIn, notes[0].boardId);
      expect(
        (await repository.fetchNotes(createdIn!))
            .any((n) => n.title == 'Nueva de Hoy'),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      protection.dispose();
      await tester.runAsync(cubit.close);
    },
  );

  testWidgets(
    'loads across lists, excludes inaccessible lists, and opens original note',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repository = LocalNotesRepository();
      final second = (await tester.runAsync(
        () => repository.createList('Trabajo'),
      ))!;
      final note = (await tester.runAsync(
        () => repository.createNote(
          second.id,
          NoteDraft(
            title: 'Revisar entrega',
            content: '',
            color: NoteColor.blue,
            authorName: 'Nico',
            reminderAt: DateTime.now().add(const Duration(days: 1)),
          ),
        ),
      ))!;
      final cubit = NotesCubit(repository);
      await tester.runAsync(cubit.load);
      expect(
        (await cubit.fetchTodayNotes(canShowList: (id) => id != second.id))
            .where((r) => r.note.id == note.id),
        isEmpty,
      );
      expect(
        (await cubit.fetchTodayNotes(canShowList: (_) => true))
            .any((r) => r.note.id == note.id),
        isTrue,
      );
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final protection = ListProtectionController();
      NoteSearchResult? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await Navigator.of(context).push<NoteSearchResult>(
                    MaterialPageRoute(
                      builder: (_) => TodayPage(
                        cubit: cubit,
                        protection: protection,
                        userId: null,
                        onCreateNote: (_, _) async {},
                        onPreviewNote: (previewContext, result) =>
                            showNotePreviewDialog(
                              context: previewContext,
                              showOpenNoteButton: true,
                              noteProvider: () => result.note,
                              assigneesProvider: () =>
                                  result.list.collaborators,
                              onSave: cubit.editNote,
                              onDelete: cubit.deleteNote,
                              cardBuilder:
                                  (
                                    _,
                                    editAssignee,
                                    editAttachment,
                                    editTarget,
                                    saveInline,
                                    closeButton,
                                  ) => PostItCard(
                                    note: result.note,
                                    layout: PostItCardLayout.large,
                                    enableHero: false,
                                    topRightOverlay: closeButton,
                                    onToggle: () {},
                                    onPin: () {},
                                    onOpen: () {},
                                    onChecklistToggle: (_) {},
                                  ),
                            ),
                      ),
                    ),
                  );
                },
                child: const Text('Abrir Hoy'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir Hoy'));
      await tester.pumpAndSettle();
      expect(find.text('Hoy'), findsOneWidget);
      expect(find.text('Próximos recordatorios · 1'), findsOneWidget);
      expect(find.textContaining('Trabajo'), findsOneWidget);
      expect(find.byKey(ValueKey('today-postpone-${note.id}')), findsNothing);
      tester.view.physicalSize = const Size(320, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('today-note-${note.id}')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revisar entrega'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('note-preview-dialog')), findsOneWidget);
      expect(selected, isNull);
      expect(find.text('Ir a la nota'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('close-note-preview-button')));
      await tester.pumpAndSettle();
      expect(find.text('Hoy'), findsOneWidget);
      expect(selected, isNull);
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('today-note-${note.id}')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Revisar entrega'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('open-note-from-preview-button')),
      );
      await tester.pumpAndSettle();
      expect(selected?.note.id, note.id);
      expect(selected?.list.id, second.id);
      await tester.pumpWidget(const SizedBox());
      protection.dispose();
      await tester.runAsync(cubit.close);
    },
  );
}

class _FailingTodayRepository extends LocalNotesRepository {
  bool failUpdates = false;

  @override
  Future<Note> updateNote(String id, Map<String, dynamic> changes) {
    if (failUpdates) throw const NotesPersistenceFailure();
    return super.updateNote(id, changes);
  }
}
