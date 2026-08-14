import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/presentation/widgets/post_it_card.dart';
import 'package:nocknock/features/notes/presentation/widgets/reminder_picker.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es');
  });

  test('serializes recurrence and keeps recurring notes pending', () {
    final note = _recurringNote(isCompleted: true);
    final restored = Note.fromJson(note.toJson());

    expect(restored.isRecurring, isTrue);
    expect(restored.isCompleted, isFalse);
    expect(
      restored.reminderRecurrence,
      const ReminderRecurrence(
        frequency: ReminderRecurrenceFrequency.monthly,
        interval: 1,
        timeZoneOffsetMinutes: -240,
        dayOfMonth: 5,
      ),
    );
  });

  test('serializes reminder times as explicit UTC instants', () {
    final reminderAt = DateTime(2026, 9, 5, 18, 37);
    final expected = reminderAt.toUtc().toIso8601String();
    final note = _recurringNote(reminderAt: reminderAt);
    final draft = NoteDraft(
      title: note.title,
      content: note.content,
      color: note.color,
      authorName: note.authorName,
      reminderAt: reminderAt,
      reminderRecurrence: note.reminderRecurrence,
    );

    expect(note.toJson()['reminderAt'], expected);
    expect(draft.toJson()['reminderAt'], expected);
    expect(expected, endsWith('Z'));
    expect(Note.fromJson(note.toJson()).reminderAt, reminderAt);
    expect(NoteDraft.fromJson(draft.toJson()).reminderAt, reminderAt);
  });

  testWidgets('creates a personalized monthly recurrence', (tester) async {
    final now = DateTime(2026, 1, 31, 9, 45);
    ReminderScheduleSelection? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                selected = await showReminderSchedulePicker(
                  context,
                  now: () => now,
                );
              },
              child: const Text('Agregar'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Agregar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reminder-recurring')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('recurrence-monthly')));
    await tester.tap(
      find.byKey(const ValueKey('recurrence-interval-increase')),
    );
    await tester.pump();
    expect(find.text('Cada 2 meses'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('save-recurring-reminder')));
    await tester.pumpAndSettle();

    expect(selected?.reminderAt, DateTime(2026, 2, 1, 9, 45));
    expect(
      selected?.recurrence?.frequency,
      ReminderRecurrenceFrequency.monthly,
    );
    expect(selected?.recurrence?.interval, 2);
    expect(selected?.recurrence?.dayOfMonth, 1);
    expect(
      selected?.recurrence?.timeZoneOffsetMinutes,
      selected?.reminderAt.timeZoneOffset.inMinutes,
    );
  });

  testWidgets('replaces the completion checkbox with a recurrence indicator', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 320,
              child: PostItCard(
                note: _recurringNote(),
                onToggle: () {},
                onPin: () {},
                onOpen: () {},
                onChecklistToggle: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    final card = find.byKey(const ValueKey('note-recurring-note'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.byType(Checkbox)),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('recurring-note-recurring-note')),
      findsOneWidget,
    );
  });

  testWidgets('recurrence setup stays usable on a narrow dark screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepOrange,
            brightness: Brightness.dark,
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.4)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showReminderSchedulePicker(
                context,
                now: () => DateTime(2026, 8, 13, 20),
              ),
              child: const Text('Agregar'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Agregar'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('reminder-recurring')),
    );
    await tester.tap(find.byKey(const ValueKey('reminder-recurring')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('recurrence-summary')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('save-recurring-reminder')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Note _recurringNote({bool isCompleted = false, DateTime? reminderAt}) => Note(
  id: 'recurring-note',
  boardId: 'home',
  title: 'Pagar tarjeta',
  content: '',
  color: NoteColor.yellow,
  authorName: 'Nico',
  isCompleted: isCompleted,
  positionX: 0,
  positionY: 0,
  reminderAt: reminderAt ?? DateTime(2026, 9, 5, 8),
  reminderRecurrence: const ReminderRecurrence(
    frequency: ReminderRecurrenceFrequency.monthly,
    interval: 1,
    timeZoneOffsetMinutes: -240,
    dayOfMonth: 5,
  ),
  createdAt: DateTime(2026, 8, 13),
  updatedAt: DateTime(2026, 8, 13),
);
