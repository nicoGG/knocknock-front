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
    final theme = Theme.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '¿Cuándo te recordamos?',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontSize: 26,
              letterSpacing: -0.7,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Elige una opción rápida o define tu propio momento.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          Material(
            key: const ValueKey('reminder-presets-group'),
            color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.72),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.42),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                const _ReminderDivider(),
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
                const _ReminderDivider(),
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
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.tonalIcon(
              key: const ValueKey('reminder-custom-date'),
              onPressed: () =>
                  Navigator.pop(context, const _ReminderChoice.custom()),
              icon: const Icon(Icons.edit_calendar_rounded),
              label: const Text('Elegir fecha y hora'),
              style: FilledButton.styleFrom(
                textStyle: theme.textTheme.titleMedium,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReminderDivider extends StatelessWidget {
  const _ReminderDivider();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Divider(
      height: 1,
      indent: 76,
      endIndent: 16,
      color: colorScheme.outlineVariant.withValues(alpha: 0.48),
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
    final theme = Theme.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final formattedDate = DateFormat("EEE d MMM · HH:mm", 'es').format(date);
    return Semantics(
      button: true,
      label: '$title, $formattedDate',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 3),
                    Text(
                      formattedDate,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: 0.58),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
