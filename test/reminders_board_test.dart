import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/presentation/widgets/reminders_board.dart';

void main() {
  final now = DateTime(2026, 11, 5, 12);
  Note note(String id, DateTime at, {bool completed = false}) => Note(
    id: id,
    boardId: 'home',
    title: 'Pagar Tarjeta Ripley $id',
    content: '',
    color: NoteColor.green,
    authorName: 'Nico',
    isCompleted: completed,
    positionX: 0,
    positionY: 0,
    createdAt: now,
    updatedAt: now,
    reminderAt: at,
  );
  test(
    'reminder filters use calendar dates and exclude completed reminders',
    () {
      final notes = [
        note('past', DateTime(2026, 11, 4, 23, 59)),
        note('early', DateTime(2026, 11, 5)),
        note('late', DateTime(2026, 11, 5, 23, 59)),
        note('next', DateTime(2026, 11, 6)),
        note('done', now, completed: true),
      ];
      expect(filterRemindersByDate(notes, ReminderDateFilter.all, now), notes);
      expect(
        filterRemindersByDate(
          notes,
          ReminderDateFilter.today,
          now,
        ).map((n) => n.id),
        ['early', 'late'],
      );
      expect(
        filterRemindersByDate(
          notes,
          ReminderDateFilter.upcoming,
          now,
        ).map((n) => n.id),
        ['next'],
      );
    },
  );

  test('groups dates chronologically and separates completed notes', () {
    final groups = groupReminderNotes([
      note('later', DateTime(2026, 12, 5)),
      note('today', now),
      note('overdue', DateTime(2026, 11, 4)),
      note('done', now, completed: true),
      note('tomorrow', DateTime(2026, 11, 6)),
    ], now);
    expect(groups['Hoy']!.single.id, 'today');
    expect(groups['Atrasados']!.single.id, 'overdue');
    expect(groups['Mañana']!.single.id, 'tomorrow');
    expect(groups['Próximamente']!.single.id, 'later');
    expect(groups['Completados']!.single.id, 'done');
  });
  for (final width in [320.0, 900.0]) {
    testWidgets('agenda fits width $width with large text and opens note', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 1000),
              textScaler: const TextScaler.linear(1.5),
            ),
            child: Scaffold(
              body: CustomScrollView(
                slivers: [
                  RemindersBoard(
                    notes: [note('today', now), note('second', now)],
                    sectionBuilder: (notes) => SliverList.list(
                      children: [
                        for (final note in notes)
                          TextButton(
                            key: ValueKey('reminder-agenda-${note.id}'),
                            onPressed: () => opened = note.id,
                            child: Text(note.title),
                          ),
                      ],
                    ),
                    now: now,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Hoy'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('reminder-agenda-today')));
      expect(opened, 'today');
    });
  }
}
