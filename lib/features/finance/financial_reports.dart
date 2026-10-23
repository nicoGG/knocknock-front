import 'package:intl/intl.dart';
import 'package:nocknock/features/finance/financial_entry.dart';
import 'package:nocknock/features/notes/domain/note.dart';

String financialMonth(DateTime date) => DateFormat('yyyy-MM').format(date);

List<Note> financialRecords(Iterable<Note> notes, {String? month}) => notes
    .where(
      (n) =>
          n.deletedAt == null &&
          n.financialEntry?.isBudget != true &&
          (month == null ||
              (n.financialEntry != null &&
                  n.financialEntry!.occursInMonth(month))),
    )
    .toList();

/// Signed balances: positive means this person should receive money. Each
/// currency is settled separately; integer remainders are assigned in order.
Map<String, Map<String, int>> sharedBalances(Iterable<Note> notes) {
  final currencies = <String, Map<String, int>>{};
  for (final note in financialRecords(notes)) {
    final e = note.financialEntry;
    if (e?.isSettlement == true) {
      final balances = currencies.putIfAbsent(e!.currency, () => {});
      balances[e.paidBy] = (balances[e.paidBy] ?? 0) + e.amountMinor;
      balances[e.counterparty] =
          (balances[e.counterparty] ?? 0) - e.amountMinor;
      continue;
    }
    if (e == null ||
        e.participants.isEmpty ||
        e.status == 'rejected' ||
        e.paidMinor == 0) {
      continue;
    }
    final balances = currencies.putIfAbsent(e.currency, () => {});
    balances[e.paidBy] = (balances[e.paidBy] ?? 0) + e.paidMinor;
    for (var i = 0; i < e.participants.length; i++) {
      final share =
          e.paidMinor ~/ e.participants.length +
          (i < e.paidMinor % e.participants.length ? 1 : 0);
      final name = e.participants[i];
      balances[name] = (balances[name] ?? 0) - share;
    }
  }
  return currencies;
}

class SharedTransfer {
  const SharedTransfer(this.from, this.to, this.amountMinor, this.currency);
  final String from;
  final String to;
  final int amountMinor;
  final String currency;
}

List<SharedTransfer> sharedTransfers(Iterable<Note> notes) {
  final transfers = <SharedTransfer>[];
  for (final group in sharedBalances(notes).entries) {
    final debtors = group.value.entries.where((e) => e.value < 0).toList();
    final creditors = group.value.entries.where((e) => e.value > 0).toList();
    final remaining = Map<String, int>.from(group.value);
    for (final debtor in debtors) {
      for (final creditor in creditors) {
        final debt = -remaining[debtor.key]!;
        final credit = remaining[creditor.key]!;
        if (debt == 0) break;
        if (credit == 0) continue;
        final amount = debt < credit ? debt : credit;
        transfers.add(
          SharedTransfer(debtor.key, creditor.key, amount, group.key),
        );
        remaining[debtor.key] = remaining[debtor.key]! + amount;
        remaining[creditor.key] = remaining[creditor.key]! - amount;
      }
    }
  }
  return transfers;
}

int budgetSpent(Iterable<Note> notes, FinancialEntry budget) =>
    financialRecords(
      notes,
      month: budget.period == 'all' ? null : budget.period,
    ).fold(0, (sum, n) {
      final e = n.financialEntry;
      return sum +
          (e == null ||
                  e.isSettlement ||
                  e.currency != budget.currency ||
                  e.status == 'rejected'
              ? 0
              : e.amountInMonth(budget.period == 'all' ? null : budget.period));
    });
