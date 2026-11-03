import 'package:nocknock/features/finance/financial_entry.dart';
import 'package:nocknock/features/finance/list_configuration.dart';
import 'package:nocknock/features/notes/data/list_protection_controller.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/logic/notes_state.dart';

NoteList? assistantList(
  NotesState state,
  String? listId,
  ListProtectionController protection,
) {
  final list = state.selectedList;
  if (list == null ||
      list.id != listId ||
      list.isEncryptionKeyPending ||
      protection.isProtected(list.id)) {
    return null;
  }
  return list;
}

String _clip(String text, int limit) {
  final value = text.trim();
  if (value.length <= limit) return value;
  final runes = value.runes.take(limit).toList();
  return String.fromCharCodes(runes) + (value.runes.length > limit ? '…' : '');
}

int _compareDates(DateTime? a, DateTime? b) {
  if (a == null) return b == null ? 0 : 1;
  return b == null ? -1 : a.compareTo(b);
}

String assistantExcerpt(NoteList list, NotesState state) {
  final notes = state.notes.where(
    (note) => note.boardId == list.id && note.deletedAt == null,
  );
  final prioritized = notes.indexed.map((item) {
    final (index, note) = item;
    final entry = note.financialEntry;
    var due = note.reminderAt;
    if (entry != null) {
      due = list.configuration.type == NoteListType.quotations
          ? entry.validUntil
          : entry.effectiveDueDate(
              receivable: list.configuration.type == NoteListType.receivables,
            );
    }
    return (
      note: note,
      entry: entry,
      closed: entry?.isClosed ?? note.isCompleted,
      due: due,
      index: index,
    );
  }).toList();
  if (prioritized.isEmpty) return '';
  prioritized.sort((a, b) {
    if (a.closed != b.closed) return a.closed ? 1 : -1;
    final dateOrder = _compareDates(a.due, b.due);
    return dateOrder != 0 ? dateOrder : a.index.compareTo(b.index);
  });
  final sample = prioritized.take(12);
  final lines = <String>[
    'Extracto parcial · ${sample.length} de ${prioritized.length} notas cargadas${state.hasMoreNotes ? ' (hay más por cargar)' : ''}.',
    'Tipo de lista: ${list.configuration.type == NoteListType.custom ? 'Financiera personalizada' : list.configuration.label}.',
  ];
  for (final item in sample) {
    final note = item.note;
    final entry = item.entry;
    final fields = <String>[_clip(note.title, 80)];
    if (entry == null) {
      fields.add(note.isCompleted ? 'completada' : 'pendiente');
      if (note.isPinned) fields.add('anclada');
      if (note.reminderAt case final time?) {
        fields.add(
          'recordatorio ${time.toLocal().toIso8601String().substring(0, 16)}',
        );
      }
      if (note.content.trim().isNotEmpty) fields.add(_clip(note.content, 160));
      for (final item in note.checklist.take(4)) {
        fields.add(
          '${item.isCompleted ? '[x]' : '[ ]'} ${_clip(item.text, 64)}',
        );
      }
      if (note.checklist.length > 4) fields.add('más subtareas omitidas');
    } else if (entry.isBudget) {
      fields.add(
        'presupuesto ${entry.formattedAmount}, período ${entry.period}',
      );
    } else {
      final installment = entry.isDeferred
          ? entry.installmentSchedule
                .where((part) => part.balanceMinor > 0)
                .firstOrNull
          : null;
      fields.addAll([
        entry.isSettlement
            ? 'liquidación'
            : list.configuration.statusLabel(entry.status),
        'monto ${entry.formattedAmount}',
        if (!entry.isSettlement &&
            list.configuration.type != NoteListType.quotations)
          'saldo ${FinancialEntry.formatAmount(entry.balanceMinor, entry.currency)}',
        if (installment != null)
          'próxima cuota ${installment.number}: ${FinancialEntry.formatAmount(installment.balanceMinor, entry.currency)}',
        if (item.due case final due?
            when list.configuration.type != NoteListType.quotations)
          'vence ${due.toIso8601String().split('T').first}',
        if (entry.validUntil case final date?)
          'válida hasta ${date.toIso8601String().split('T').first}',
      ]);
    }
    lines.add('• ${fields.join(' · ')}');
  }
  return _clip(lines.join('\n'), 7999);
}
