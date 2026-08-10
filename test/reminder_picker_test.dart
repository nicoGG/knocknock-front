import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nocknock/features/notes/presentation/widgets/reminder_picker.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es');
  });

  test('builds day and week presets from the current minute', () {
    final now = DateTime(2026, 8, 10, 14, 37, 52, 300);

    expect(
      reminderDateForPreset(ReminderPreset.day, now),
      DateTime(2026, 8, 11, 14, 37),
    );
    expect(
      reminderDateForPreset(ReminderPreset.week, now),
      DateTime(2026, 8, 17, 14, 37),
    );
  });

  test('clamps a month preset to the last valid day', () {
    expect(
      reminderDateForPreset(ReminderPreset.month, DateTime(2026, 1, 31, 9, 45)),
      DateTime(2026, 2, 28, 9, 45),
    );
  });

  testWidgets('offers quick reminder choices and selects one month', (
    tester,
  ) async {
    final now = DateTime(2026, 1, 31, 9, 45);
    DateTime? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                selected = await showReminderPicker(context, now: () => now);
              },
              child: const Text('Recordatorio'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Recordatorio'));
    await tester.pumpAndSettle();

    expect(find.text('Dentro de 1 día'), findsOneWidget);
    expect(find.text('Dentro de 1 semana'), findsOneWidget);
    expect(find.text('Dentro de 1 mes'), findsOneWidget);
    expect(find.text('Elegir fecha y hora'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('reminder-preset-month')));
    await tester.pumpAndSettle();

    expect(selected, DateTime(2026, 2, 28, 9, 45));
  });
}
