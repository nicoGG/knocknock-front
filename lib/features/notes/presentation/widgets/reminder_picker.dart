import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:nocknock/features/notes/domain/note.dart';

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

class ReminderScheduleSelection {
  const ReminderScheduleSelection({required this.reminderAt, this.recurrence});

  final DateTime reminderAt;
  final ReminderRecurrence? recurrence;
}

Future<DateTime?> showReminderPicker(
  BuildContext context, {
  DateTime? currentReminder,
  DateTime Function()? now,
}) async {
  final selection = await showReminderSchedulePicker(
    context,
    currentReminder: currentReminder,
    now: now,
  );
  return selection?.reminderAt;
}

Future<ReminderScheduleSelection?> showReminderSchedulePicker(
  BuildContext context, {
  DateTime? currentReminder,
  ReminderRecurrence? currentRecurrence,
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
    return ReminderScheduleSelection(
      reminderAt: reminderDateForPreset(preset, currentTime),
    );
  }

  if (choice.isRecurring) {
    return showModalBottomSheet<ReminderScheduleSelection>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (sheetContext) => _RecurringReminderSheet(
        now: currentTime,
        currentReminder: currentReminder,
        currentRecurrence: currentRecurrence,
      ),
    );
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

  return ReminderScheduleSelection(
    reminderAt: DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ),
  );
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
  const _ReminderChoice.preset(this.preset) : isRecurring = false;
  const _ReminderChoice.custom() : preset = null, isRecurring = false;
  const _ReminderChoice.recurring() : preset = null, isRecurring = true;

  final ReminderPreset? preset;
  final bool isRecurring;
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
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: OutlinedButton.icon(
              key: const ValueKey('reminder-recurring'),
              onPressed: () =>
                  Navigator.pop(context, const _ReminderChoice.recurring()),
              icon: const Icon(Icons.repeat_rounded),
              label: const Text('Crear recordatorio recurrente'),
              style: OutlinedButton.styleFrom(
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

String reminderRecurrenceLabel(
  ReminderRecurrence recurrence,
  DateTime reminderAt, {
  bool includeTime = false,
}) {
  final interval = recurrence.interval;
  final base = switch (recurrence.frequency) {
    ReminderRecurrenceFrequency.daily =>
      interval == 1 ? 'Todos los días' : 'Cada $interval días',
    ReminderRecurrenceFrequency.weekly =>
      interval == 1
          ? 'Cada semana, los ${DateFormat('EEEE', 'es').format(reminderAt)}'
          : 'Cada $interval semanas, los ${DateFormat('EEEE', 'es').format(reminderAt)}',
    ReminderRecurrenceFrequency.monthly =>
      interval == 1
          ? 'Cada mes, el día ${recurrence.dayOfMonth ?? reminderAt.day}'
          : 'Cada $interval meses, el día ${recurrence.dayOfMonth ?? reminderAt.day}',
  };
  return includeTime
      ? '$base · ${DateFormat('HH:mm', 'es').format(reminderAt)}'
      : base;
}

class _RecurringReminderSheet extends StatefulWidget {
  const _RecurringReminderSheet({
    required this.now,
    required this.currentReminder,
    required this.currentRecurrence,
  });

  final DateTime now;
  final DateTime? currentReminder;
  final ReminderRecurrence? currentRecurrence;

  @override
  State<_RecurringReminderSheet> createState() =>
      _RecurringReminderSheetState();
}

class _RecurringReminderSheetState extends State<_RecurringReminderSheet> {
  late ReminderRecurrenceFrequency _frequency;
  late int _interval;
  late DateTime _start;
  String? _timeZoneId;

  @override
  void initState() {
    super.initState();
    final current = widget.currentReminder;
    _start = current != null && current.isAfter(widget.now)
        ? current
        : DateTime(
            widget.now.year,
            widget.now.month,
            widget.now.day + 1,
            widget.now.hour,
            widget.now.minute,
          );
    _frequency =
        widget.currentRecurrence?.frequency ??
        ReminderRecurrenceFrequency.daily;
    _interval = widget.currentRecurrence?.interval ?? 1;
    _timeZoneId = widget.currentRecurrence?.timeZoneId;
    _loadDeviceTimeZone();
  }

  ReminderRecurrence get _recurrence => ReminderRecurrence(
    frequency: _frequency,
    interval: _interval,
    timeZoneOffsetMinutes: _start.timeZoneOffset.inMinutes,
    timeZoneId: _timeZoneId,
    dayOfMonth: _frequency == ReminderRecurrenceFrequency.monthly
        ? _start.day
        : null,
  );

  Future<void> _loadDeviceTimeZone() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      if (mounted && info.identifier.trim().isNotEmpty) {
        setState(() => _timeZoneId = info.identifier.trim());
      }
    } on Object {
      // The numeric offset remains a safe fallback on unsupported platforms.
    }
  }

  Future<void> _pickDate() async {
    final today = DateTime(widget.now.year, widget.now.month, widget.now.day);
    final date = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: today,
      lastDate: widget.now.add(const Duration(days: 3650)),
    );
    if (date == null || !mounted) return;
    setState(() {
      _start = DateTime(
        date.year,
        date.month,
        date.day,
        _start.hour,
        _start.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_start),
    );
    if (time == null || !mounted) return;
    setState(() {
      _start = DateTime(
        _start.year,
        _start.month,
        _start.day,
        time.hour,
        time.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isValid = _start.isAfter(widget.now);
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RecurringReminderHeader(
            titleStyle: theme.textTheme.headlineSmall,
            subtitleStyle: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          Text(
            'FRECUENCIA',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          _RecurrenceFrequencySelector(
            selected: _frequency,
            onChanged: (frequency) => setState(() => _frequency = frequency),
          ),
          const SizedBox(height: 12),
          _RecurrenceIntervalControl(
            label: _interval == 1
                ? 'Cada ${_frequencyUnit(singular: true)}'
                : 'Cada $_interval ${_frequencyUnit(singular: false)}',
            canDecrease: _interval > 1,
            canIncrease: _interval < 99,
            onDecrease: () => setState(() => _interval--),
            onIncrease: () => setState(() => _interval++),
          ),
          const SizedBox(height: 12),
          _RecurrenceScheduleFields(
            start: _start,
            stack: textScale > 1.2,
            onPickDate: _pickDate,
            onPickTime: _pickTime,
          ),
          const SizedBox(height: 12),
          _RecurrenceSummary(
            key: const ValueKey('recurrence-summary'),
            label: reminderRecurrenceLabel(
              _recurrence,
              _start,
              includeTime: true,
            ),
          ),
          if (!isValid) ...[
            const SizedBox(height: 10),
            Text(
              'El primer aviso debe quedar en el futuro.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const ValueKey('save-recurring-reminder'),
            onPressed: isValid
                ? () => Navigator.pop(
                    context,
                    ReminderScheduleSelection(
                      reminderAt: _start,
                      recurrence: _recurrence,
                    ),
                  )
                : null,
            icon: const Icon(Icons.notifications_active_rounded),
            label: const Text('Guardar recordatorio'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              textStyle: theme.textTheme.titleMedium,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(17),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _frequencyUnit({required bool singular}) => switch (_frequency) {
    ReminderRecurrenceFrequency.daily => singular ? 'día' : 'días',
    ReminderRecurrenceFrequency.weekly => singular ? 'semana' : 'semanas',
    ReminderRecurrenceFrequency.monthly => singular ? 'mes' : 'meses',
  };
}

class _RecurringReminderHeader extends StatelessWidget {
  const _RecurringReminderHeader({
    required this.titleStyle,
    required this.subtitleStyle,
  });

  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(Icons.repeat_rounded, color: colorScheme.primary),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Repetir recordatorio',
                style: titleStyle?.copyWith(fontSize: 22, letterSpacing: -0.4),
              ),
              const SizedBox(height: 3),
              Text(
                'Vuelve a avisarte sin marcar la nota como completada.',
                style: subtitleStyle?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecurrenceFrequencySelector extends StatelessWidget {
  const _RecurrenceFrequencySelector({
    required this.selected,
    required this.onChanged,
  });

  final ReminderRecurrenceFrequency selected;
  final ValueChanged<ReminderRecurrenceFrequency> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackContent = constraints.maxWidth < 330 || textScale > 1.2;
        return Container(
          key: const ValueKey('recurrence-frequency-selector'),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.38),
            ),
          ),
          child: Row(
            children: [
              for (final frequency in ReminderRecurrenceFrequency.values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _RecurrenceFrequencyOption(
                      key: ValueKey('recurrence-${frequency.name}'),
                      frequency: frequency,
                      selected: selected == frequency,
                      stackContent: stackContent,
                      duration: disableAnimations
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      onTap: () => onChanged(frequency),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _RecurrenceFrequencyOption extends StatelessWidget {
  const _RecurrenceFrequencyOption({
    required this.frequency,
    required this.selected,
    required this.stackContent,
    required this.duration,
    required this.onTap,
    super.key,
  });

  final ReminderRecurrenceFrequency frequency;
  final bool selected;
  final bool stackContent;
  final Duration duration;
  final VoidCallback onTap;

  String get _label => switch (frequency) {
    ReminderRecurrenceFrequency.daily => 'Días',
    ReminderRecurrenceFrequency.weekly => 'Semanas',
    ReminderRecurrenceFrequency.monthly => 'Meses',
  };

  IconData get _icon => switch (frequency) {
    ReminderRecurrenceFrequency.daily => Icons.today_rounded,
    ReminderRecurrenceFrequency.weekly => Icons.view_week_rounded,
    ReminderRecurrenceFrequency.monthly => Icons.calendar_month_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final foreground = selected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;
    final content = stackContent
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_icon, size: 18, color: foreground),
              const SizedBox(height: 3),
              Text(
                _label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_icon, size: 18, color: foreground),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          );

    return Semantics(
      selected: selected,
      button: true,
      label: _label,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOutCubic,
            alignment: Alignment.center,
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? colorScheme.primaryContainer.withValues(alpha: 0.82)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: colorScheme.primary.withValues(alpha: 0.1),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

class _RecurrenceIntervalControl extends StatelessWidget {
  const _RecurrenceIntervalControl({
    required this.label,
    required this.canDecrease,
    required this.canIncrease,
    required this.onDecrease,
    required this.onIncrease,
  });

  final String label;
  final bool canDecrease;
  final bool canIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 9, 8, 9),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.autorenew_rounded,
              size: 20,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'INTERVALO',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                Text(
                  label,
                  key: const ValueKey('recurrence-interval-label'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          _RecurrenceStepButton(
            key: const ValueKey('recurrence-interval-decrease'),
            icon: Icons.remove_rounded,
            tooltip: 'Disminuir intervalo',
            onPressed: canDecrease ? onDecrease : null,
          ),
          const SizedBox(width: 4),
          _RecurrenceStepButton(
            key: const ValueKey('recurrence-interval-increase'),
            icon: Icons.add_rounded,
            tooltip: 'Aumentar intervalo',
            onPressed: canIncrease ? onIncrease : null,
          ),
        ],
      ),
    );
  }
}

class _RecurrenceStepButton extends StatelessWidget {
  const _RecurrenceStepButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton.filledTonal(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        minimumSize: const Size.square(38),
        maximumSize: const Size.square(38),
        padding: EdgeInsets.zero,
        backgroundColor: colorScheme.surfaceContainerHighest,
      ),
    );
  }
}

class _RecurrenceScheduleFields extends StatelessWidget {
  const _RecurrenceScheduleFields({
    required this.start,
    required this.stack,
    required this.onPickDate,
    required this.onPickTime,
  });

  final DateTime start;
  final bool stack;
  final VoidCallback onPickDate;
  final VoidCallback onPickTime;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useStack = stack || constraints.maxWidth < 340;
        final date = _RecurrenceScheduleField(
          key: const ValueKey('recurrence-start-date'),
          icon: Icons.calendar_today_rounded,
          label: 'Comienza',
          value: DateFormat('d MMM y', 'es').format(start),
          onTap: onPickDate,
        );
        final time = _RecurrenceScheduleField(
          key: const ValueKey('recurrence-time'),
          icon: Icons.schedule_rounded,
          label: 'Hora',
          value: TimeOfDay.fromDateTime(start).format(context),
          onTap: onPickTime,
        );
        if (useStack) {
          return Column(children: [date, const SizedBox(height: 8), time]);
        }
        return Row(
          children: [
            Expanded(child: date),
            const SizedBox(width: 8),
            Expanded(child: time),
          ],
        );
      },
    );
  }
}

class _RecurrenceScheduleField extends StatelessWidget {
  const _RecurrenceScheduleField({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 11, 9, 11),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: colorScheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecurrenceSummary extends StatelessWidget {
  const _RecurrenceSummary({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 14, 11),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary.withValues(alpha: isDark ? 0.2 : 0.13),
            colorScheme.primaryContainer.withValues(
              alpha: isDark ? 0.38 : 0.52,
            ),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: isDark ? 0.34 : 0.6),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              Icons.notifications_active_rounded,
              size: 21,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'PRÓXIMO AVISO',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
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
