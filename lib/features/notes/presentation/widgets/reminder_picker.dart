import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum ReminderPreset { day, week, month }

DateTime reminderDateForPreset(ReminderPreset preset, DateTime now) {
  final minuteNow = DateTime(
    now.year,
    now.month,
    now.day,
    now.hour,
    now.minute,
  );
  return switch (preset) {
    ReminderPreset.day => minuteNow.add(const Duration(days: 1)),
    ReminderPreset.week => minuteNow.add(const Duration(days: 7)),
    ReminderPreset.month => _addCalendarMonth(minuteNow),
  };
}

Future<DateTime?> showReminderPicker(
  BuildContext context, {
  DateTime? currentReminder,
  DateTime Function()? now,
}) async {
  final currentTime = (now ?? DateTime.now)();
  final choice = await showModalBottomSheet<_ReminderChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => _ReminderPickerSheet(now: currentTime),
  );
  if (choice == null || !context.mounted) return null;

  if (choice.preset case final preset?) {
    return reminderDateForPreset(preset, currentTime);
  }

  final today = DateTime(currentTime.year, currentTime.month, currentTime.day);
  final lastDate = currentTime.add(const Duration(days: 730));
  final validCurrentReminder =
      currentReminder != null &&
      !currentReminder.isBefore(today) &&
      !currentReminder.isAfter(lastDate);
  final initialDate = validCurrentReminder ? currentReminder : today;
  final date = await showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: today,
    lastDate: lastDate,
  );
  if (date == null || !context.mounted) return null;

  final initialTime = validCurrentReminder ? currentReminder : currentTime;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initialTime),
  );
  if (time == null) return null;

  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

DateTime _addCalendarMonth(DateTime date) {
  final targetMonth = DateTime(date.year, date.month + 1);
  final lastDayOfTargetMonth = DateTime(
    targetMonth.year,
    targetMonth.month + 1,
    0,
  ).day;
  return DateTime(
    targetMonth.year,
    targetMonth.month,
    date.day.clamp(1, lastDayOfTargetMonth),
    date.hour,
    date.minute,
  );
}

class _ReminderChoice {
  const _ReminderChoice.preset(this.preset);
  const _ReminderChoice.custom() : preset = null;

  final ReminderPreset? preset;
}

class _ReminderPickerSheet extends StatelessWidget {
  const _ReminderPickerSheet({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '¿Cuándo te recordamos?',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            'Elige una opción rápida o una fecha exacta.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          _ReminderPresetTile(
            key: const ValueKey('reminder-preset-day'),
            icon: Icons.today_rounded,
            title: 'Dentro de 1 día',
            date: reminderDateForPreset(ReminderPreset.day, now),
            onTap: () => Navigator.pop(
              context,
              const _ReminderChoice.preset(ReminderPreset.day),
            ),
          ),
          const SizedBox(height: 8),
          _ReminderPresetTile(
            key: const ValueKey('reminder-preset-week'),
            icon: Icons.date_range_rounded,
            title: 'Dentro de 1 semana',
            date: reminderDateForPreset(ReminderPreset.week, now),
            onTap: () => Navigator.pop(
              context,
              const _ReminderChoice.preset(ReminderPreset.week),
            ),
          ),
          const SizedBox(height: 8),
          _ReminderPresetTile(
            key: const ValueKey('reminder-preset-month'),
            icon: Icons.calendar_month_rounded,
            title: 'Dentro de 1 mes',
            date: reminderDateForPreset(ReminderPreset.month, now),
            onTap: () => Navigator.pop(
              context,
              const _ReminderChoice.preset(ReminderPreset.month),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const ValueKey('reminder-custom-date'),
              onPressed: () =>
                  Navigator.pop(context, const _ReminderChoice.custom()),
              icon: const Icon(Icons.edit_calendar_rounded),
              label: const Text('Elegir fecha y hora'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReminderPresetTile extends StatelessWidget {
  const _ReminderPresetTile({
    required this.icon,
    required this.title,
    required this.date,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.primaryContainer.withValues(alpha: 0.46),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: colorScheme.primary),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat("EEE d MMM · HH:mm", 'es').format(date),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
