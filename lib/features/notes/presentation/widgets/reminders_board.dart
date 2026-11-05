import 'package:flutter/material.dart';
import 'package:nocknock/features/notes/domain/note.dart';

enum ReminderDateFilter { all, today, upcoming }

List<Note> filterRemindersByDate(
  List<Note> notes,
  ReminderDateFilter filter,
  DateTime now,
) {
  if (filter == ReminderDateFilter.all) return notes;
  final local = now.toLocal();
  final today = DateTime(local.year, local.month, local.day);
  final tomorrow = DateTime(local.year, local.month, local.day + 1);
  return notes.where((note) {
    final date = note.reminderAt?.toLocal();
    if (date == null || note.isCompleted) return false;
    return filter == ReminderDateFilter.today
        ? !date.isBefore(today) && date.isBefore(tomorrow)
        : !date.isBefore(tomorrow);
  }).toList();
}

Map<String, List<Note>> groupReminderNotes(List<Note> notes, DateTime now) {
  final today = DateUtils.dateOnly(now.toLocal());
  final tomorrow = DateTime(today.year, today.month, today.day + 1);
  final afterTomorrow = DateTime(today.year, today.month, today.day + 2);
  final groups = <String, List<Note>>{
    'Atrasados': [],
    'Hoy': [],
    'Mañana': [],
    'Próximamente': [],
    'Completados': [],
  };
  final sorted =
      notes.where((n) => n.reminderAt != null && n.deletedAt == null).toList()
        ..sort((a, b) => a.reminderAt!.compareTo(b.reminderAt!));
  for (final note in sorted) {
    final date = note.reminderAt!.toLocal();
    final section = note.isCompleted
        ? 'Completados'
        : date.isBefore(today)
        ? 'Atrasados'
        : date.isBefore(tomorrow)
        ? 'Hoy'
        : date.isBefore(afterTomorrow)
        ? 'Mañana'
        : 'Próximamente';
    groups[section]!.add(note);
  }
  return groups;
}

/// Date sections around the board’s existing card layouts.
class RemindersBoard extends StatelessWidget {
  const RemindersBoard({
    super.key,
    required this.notes,
    required this.sectionBuilder,
    this.now,
  });

  final List<Note> notes;
  final Widget Function(List<Note>) sectionBuilder;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final clock = now ?? DateTime.now();
    final groups = groupReminderNotes(notes, clock);
    final colors = Theme.of(context).colorScheme;
    final pending = groups.entries
        .where((e) => e.key != 'Completados')
        .expand((e) => e.value)
        .length;
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colors.primaryContainer.withValues(alpha: .35),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: colors.primary.withValues(alpha: .16)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.notifications_active_outlined,
                  color: colors.primary,
                  size: 28,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pending == 1
                            ? '1 recordatorio pendiente'
                            : '$pending recordatorios pendientes',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'En orden de fecha · ${groups['Hoy']!.length} para hoy',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        for (final entry in groups.entries)
          if (entry.value.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                child: Row(
                  children: [
                    Icon(
                      entry.key == 'Hoy'
                          ? Icons.today_outlined
                          : entry.key == 'Atrasados'
                          ? Icons.history_rounded
                          : entry.key == 'Completados'
                          ? Icons.task_alt
                          : Icons.event_outlined,
                      size: 18,
                      color: entry.key == 'Atrasados'
                          ? colors.error
                          : colors.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      entry.key,
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${entry.value.length}',
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
            sectionBuilder(entry.value),
          ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}
