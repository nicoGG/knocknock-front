import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:nocknock/features/finance/financial_entry.dart';
import 'package:nocknock/features/finance/list_configuration.dart';
import 'package:nocknock/features/notes/data/notes_repository.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:uuid/uuid.dart';

/// Stored in the same encrypted financial field as entries, separately from
/// the notes that hold each month's payments, history and attachments.
class MonthlyFinanceRule {
  const MonthlyFinanceRule({
    required this.start,
    required this.amount,
    required this.currency,
    required this.counterparty,
    this.next = 0,
  });
  final DateTime start;
  final int amount;
  final String currency;
  final String counterparty;
  final int next;

  // The next calendar month is available for the agenda. A scheduled series
  // that starts later still gets its first record immediately.
  static int periodsThroughNextMonth(DateTime first, DateTime now) {
    final end = DateTime(now.year, now.month + 1);
    final count = (end.year - first.year) * 12 + end.month - first.month + 1;
    return count < 1 ? 1 : count;
  }

  String encode({int? nextMonth}) => jsonEncode({
    'kind': 'monthlySeries',
    'version': 1,
    'start': DateFormat('yyyy-MM-dd').format(start),
    'amountMinor': amount,
    'currency': currency,
    'counterparty': counterparty,
    'next': nextMonth ?? next,
  });

  static MonthlyFinanceRule? decode(String? raw) {
    if (raw == null || !raw.contains('"monthlySeries"')) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map ||
          data['kind'] != 'monthlySeries' ||
          data['version'] != 1) {
        return null;
      }
      final start = DateTime.parse(data['start'] as String);
      final amount = data['amountMinor'] as int;
      final next = data['next'] as int;
      if (DateFormat('yyyy-MM-dd').format(start) != data['start'] ||
          start.year < 2000 ||
          start.year > 2100 ||
          amount <= 0 ||
          amount > FinancialEntry.maxAmountMinor ||
          next < 0 ||
          next > 100000 ||
          !ListConfiguration.currencies.contains(data['currency'])) {
        return null;
      }
      return MonthlyFinanceRule(
        start: start,
        amount: amount,
        currency: data['currency'] as String,
        counterparty: data['counterparty'] as String,
        next: next,
      );
    } on Object {
      return null;
    }
  }
}

class MonthlyFinanceSeries {
  MonthlyFinanceSeries(this.repository);
  final NotesRepository repository;
  final _active = <String, Future<List<Note>>>{};

  Future<List<Note>> load(
    String boardId, {
    DateTime? now,
    bool materialize = true,
  }) => !materialize
      ? repository
            .fetchNotes(boardId)
            .then(
              (notes) => notes
                  .where(
                    (n) =>
                        n.deletedAt == null &&
                        MonthlyFinanceRule.decode(n.financialData) == null,
                  )
                  .toList(),
            )
      : (_active[boardId] ??= _load(boardId, now ?? DateTime.now())
            .whenComplete(() {
              _active.remove(boardId);
            }));

  Future<List<Note>> afterCreate(String boardId) async {
    final running = _active[boardId];
    if (running != null) await running;
    return load(boardId);
  }

  Future<List<Note>> _load(String boardId, DateTime now) async {
    final notes = await repository.fetchNotes(boardId);
    final byId = {for (final note in notes) note.id: note};
    if (repository case final NotesCacheReader cacheReader) {
      if (notes.any(
        (n) => MonthlyFinanceRule.decode(n.financialData) != null,
      )) {
        final snapshot = await cacheReader.readCache();
        if (snapshot != null &&
            !snapshot.fullyLoadedBoardIds.contains(boardId)) {
          throw const NotesPersistenceFailure();
        }
      }
    }
    for (final template in notes) {
      final rule = MonthlyFinanceRule.decode(template.financialData);
      if (rule == null || template.deletedAt != null) continue;
      final last =
          MonthlyFinanceRule.periodsThroughNextMonth(rule.start, now) - 1;
      if (rule.next > last) continue;
      var index = rule.next;
      while (index <= last) {
        final date = financialMonthOffset(rule.start, index);
        final id = const Uuid().v5(
          Namespace.url.value,
          'nocknock/monthly/$boardId/${template.id}/$index',
        );
        if (!byId.containsKey(id)) {
          final draft = NoteDraft(
            title: template.title,
            content: '',
            color: template.color,
            category: NoteCategory.finance,
            authorName: template.authorName,
            financialData: FinancialEntry(
              amountMinor: rule.amount,
              currency: rule.currency,
              counterparty: rule.counterparty,
              date: date,
              dueDate: date,
            ).encoded,
            clientNoteId: id,
            clientMutationId: id,
          );
          try {
            final note = await repository.createNote(boardId, draft);
            if (note.deletedAt == null) byId[id] = note;
          } catch (_) {
            // A second collaborator can win the unique note ID between reads.
            final concurrent = (await repository.fetchNotes(boardId))
                .where((n) => n.id == id)
                .firstOrNull;
            if (concurrent == null) rethrow;
            byId[id] = concurrent;
          }
        }
        index++;
      }
      try {
        byId[template.id] = await repository.updateNote(template.id, {
          'expectedRevision': template.revision,
          'clientMutationId': const Uuid().v5(
            Namespace.url.value,
            'nocknock/monthly-cursor/$boardId/${template.id}/$index',
          ),
          'financialData': rule.encode(nextMonth: index),
        });
      } catch (_) {
        final current = (await repository.fetchNotes(boardId))
            .where((n) => n.id == template.id)
            .firstOrNull;
        if (current != null &&
            (MonthlyFinanceRule.decode(current.financialData)?.next ?? 0) <
                index) {
          rethrow;
        }
      }
    }
    return byId.values
        .where(
          (n) =>
              MonthlyFinanceRule.decode(n.financialData) == null &&
              n.deletedAt == null,
        )
        .toList();
  }
}
