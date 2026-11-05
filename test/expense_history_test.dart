import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/personal_expenses/expense_history.dart';

import 'personal_expenses_test.dart' show sampleStatement;

Map<String, dynamic> month(
  String date, {
  String account = '1234',
  int purchases = 30000,
  int refunds = 0,
  int charges = 0,
}) => {
  ...sampleStatement(),
  'billingDate': date,
  'contractLast4': account,
  'totals': {
    'purchases': purchases,
    'refunds': refunds,
    'charges': charges,
    'payments': -999999,
    'billed': purchases + refunds + charges,
    'difference': 0,
  },
};
void main() {
  test(
    'groups multiple accounts by billing month and keeps history sorted',
    () {
      final history = ExpenseHistory([
        month('2026-10-24'),
        month('2026-11-24'),
        month('2026-11-25', account: '9999'),
      ]);
      expect(history.months.map((m) => m.key), ['2026-11', '2026-10']);
      expect(history.months.first.net, 60000);
      expect(history.delta(history.months.first), isNull);
    },
  );
  test('compares adjacent months across years with signed refunds and no payment duplication', () {
    final history = ExpenseHistory([
      month('2026-12-24'),
      month('2027-01-24', purchases: 40000, refunds: -10000, charges: 1000),
    ]);
    final current = history.months.first;
    expect(current.net, 31000);
    expect(history.delta(current), 1000);
    expect(history.percent(current), closeTo(3.3333, .001));
    expect(current.installmentCharges, 30000);
    expect(current.pendingPurchases, 1);
    expect(current.merchants.values, [30000]);
  });
  test(
    'missing months and zero baselines do not create misleading percentages',
    () {
      final missing = ExpenseHistory([
        month('2026-09-24'),
        month('2026-11-24'),
      ]);
      expect(missing.delta(missing.months.first), isNull);
      expect(missing.month('2026-10'), isNull);
      final zero = ExpenseHistory([
        month('2026-10-24', purchases: 0),
        month('2026-11-24'),
      ]);
      expect(zero.delta(zero.months.first), 30000);
      expect(zero.percent(zero.months.first), isNull);
    },
  );
  test('ongoing installments are not mislabeled as habitual purchases', () {
    final history = ExpenseHistory([month('2026-10-24'), month('2026-11-24')]);
    expect(history.recurringMerchants(history.months.first), isEmpty);
  });
}
