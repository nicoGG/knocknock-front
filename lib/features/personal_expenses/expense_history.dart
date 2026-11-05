/// Summaries use billing months and billed installments, never the original
/// purchase principal. Missing months are unknown, not zero spending.
class ExpenseMonth {
  ExpenseMonth(this.key, this.statements);
  final String key;
  final List<Map<String, dynamic>> statements;
  int sum(String field) => statements.fold(
    0,
    (sum, s) => sum + ((s['totals'] as Map)[field] as num).toInt(),
  );
  int get net => sum('billed');
  int get invoiced =>
      statements.fold(0, (sum, s) => sum + (s['totalBilled'] as num).toInt());
  Set<String> get accounts =>
      statements.map((s) => '${s['issuer']}|${s['contractLast4']}').toSet();
  List<Map<String, dynamic>> get movements => statements
      .expand(
        (s) => (s['movements'] as List).map(
          (m) => Map<String, dynamic>.from(m as Map),
        ),
      )
      .toList();
  int get installmentCharges => movements
      .where(
        (m) => m['kind'] == 'purchase' && (m['installments'] as num? ?? 0) > 1,
      )
      .fold(0, (sum, m) => sum + (m['billedAmount'] as num).toInt());
  int get pendingPurchases =>
      movements.where((m) => m['installment'] == 0).length;
  Map<String, int> get merchants => _group('description');
  Map<String, int> get sections => _group('section');
  Map<String, int> _group(String field) {
    final result = <String, int>{};
    for (final m in movements.where((m) => m['kind'] == 'purchase')) {
      final key = (m[field] as String).trim();
      result[key] = (result[key] ?? 0) + (m['billedAmount'] as num).toInt();
    }
    result.removeWhere((_, amount) => amount <= 0);
    return Map.fromEntries(
      result.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
  }
}

class ExpenseHistory {
  ExpenseHistory(List<Map<String, dynamic>> statements) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final statement in statements) {
      final key = (statement['billingDate'] as String).substring(0, 7);
      grouped.putIfAbsent(key, () => []).add(statement);
    }
    months = grouped.entries.map((e) => ExpenseMonth(e.key, e.value)).toList()
      ..sort((a, b) => b.key.compareTo(a.key));
  }
  late final List<ExpenseMonth> months;
  ExpenseMonth? month(String key) {
    for (final month in months) {
      if (month.key == key) return month;
    }
    return null;
  }

  ExpenseMonth? previous(ExpenseMonth selected) {
    final date = DateTime.parse('${selected.key}-01');
    final previous = DateTime(date.year, date.month - 1);
    return month(
      '${previous.year}-${previous.month.toString().padLeft(2, '0')}',
    );
  }

  bool comparable(ExpenseMonth current) {
    final prior = previous(current);
    return prior != null &&
        current.accounts.length == prior.accounts.length &&
        current.accounts.containsAll(prior.accounts);
  }

  int? delta(ExpenseMonth selected) =>
      comparable(selected) ? selected.net - previous(selected)!.net : null;
  double? percent(ExpenseMonth selected) {
    final change = delta(selected);
    final prior = previous(selected)?.net;
    return change == null || prior == null || prior <= 0
        ? null
        : change / prior * 100;
  }

  List<String> recurringMerchants(ExpenseMonth selected) {
    final prior = previous(selected);
    if (prior == null || !comparable(selected)) return [];
    Set<String> names(ExpenseMonth month) => month.movements
        .where(
          (m) =>
              m['kind'] == 'purchase' &&
              (m['installments'] as num? ?? 1) <= 1 &&
              (m['billedAmount'] as num) > 0,
        )
        .map((m) => (m['description'] as String).trim().toLowerCase())
        .toSet();
    return names(selected).intersection(names(prior)).toList()..sort();
  }
}
