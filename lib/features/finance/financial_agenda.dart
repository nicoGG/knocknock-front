import 'package:nocknock/features/finance/list_configuration.dart';
import 'package:nocknock/features/notes/data/notes_repository.dart';

enum AgendaPeriod {
  week('Esta semana'),
  nextWeek('Próxima semana'),
  overdue('Vencidos'),
  all('Todos');

  const AgendaPeriod(this.label);
  final String label;
  bool includes(DateTime date, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final monday = DateTime(
      today.year,
      today.month,
      today.day - today.weekday + 1,
    );
    final start = DateTime(
      monday.year,
      monday.month,
      monday.day + (this == nextWeek ? 7 : 0),
    );
    return switch (this) {
      all => true,
      overdue => date.isBefore(today),
      _ =>
        !date.isBefore(start) &&
            date.isBefore(DateTime(start.year, start.month, start.day + 7)),
    };
  }
}

class AgendaDue {
  const AgendaDue(
    this.source,
    this.date,
    this.balance,
    this.currency,
    this.receivable,
    this.counterparty, {
    this.installment,
    this.count,
    this.firstUnpaid = true,
  });
  final NoteSearchResult source;
  final DateTime date;
  final int balance;
  final String currency;
  final bool receivable;
  final String counterparty;
  final int? installment;
  final int? count;
  final bool firstUnpaid;
}

bool isAgendaType(NoteListType type) =>
    type == NoteListType.expenses || type == NoteListType.receivables;

List<AgendaDue> agendaDues(Iterable<NoteSearchResult> records) {
  final dues = <AgendaDue>[];
  for (final source in records) {
    final type = source.list.configuration.type;
    final entry = source.note.financialEntry;
    if (!isAgendaType(type) ||
        source.note.deletedAt != null ||
        entry == null ||
        entry.kind != 'entry' ||
        entry.isClosed ||
        entry.balanceMinor <= 0) {
      continue;
    }
    final receivable = type == NoteListType.receivables;
    if (entry.isDeferred) {
      var first = true;
      for (final part in entry.installmentSchedule.where(
        (p) => p.balanceMinor > 0,
      )) {
        dues.add(
          AgendaDue(
            source,
            part.date,
            part.balanceMinor,
            entry.currency,
            receivable,
            entry.counterparty,
            installment: part.number,
            count: entry.installments,
            firstUnpaid: first,
          ),
        );
        first = false;
      }
    } else {
      final due = entry.effectiveDueDate(receivable: receivable);
      if (due != null) {
        dues.add(
          AgendaDue(
            source,
            due,
            entry.balanceMinor,
            entry.currency,
            receivable,
            entry.counterparty,
          ),
        );
      }
    }
  }
  return dues..sort((a, b) {
    final date = a.date.compareTo(b.date);
    if (date != 0) return date;
    return a.source.note.title.compareTo(b.source.note.title);
  });
}
