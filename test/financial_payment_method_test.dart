import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nocknock/features/finance/financial_entry.dart';
import 'package:nocknock/features/finance/financial_entry_editor.dart';
import 'package:nocknock/features/finance/financial_style.dart';
import 'package:nocknock/features/notes/domain/note.dart';

import 'financial_improvements_test.dart' as f;

void main() {
  setUpAll(() => initializeDateFormatting('es'));
  test(
    'methods and credit installments round trip on entries and payments',
    () {
      for (final method in financialPaymentMethods) {
        final entry = FinancialEntry(
          amountMinor: 1000,
          currency: 'CLP',
          counterparty: 'Ana',
          date: DateTime(2026, 10, 22),
          paymentMethod: method,
          installments: method == 'credit' ? 6 : null,
          payments: [
            FinancialPayment(
              id: 'p',
              amountMinor: 100,
              date: DateTime(2026, 10, 22),
              paymentMethod: method,
              installments: method == 'credit' ? 3 : null,
            ),
          ],
        );
        final decoded = FinancialEntry.tryDecode(entry.encoded)!;
        expect(decoded, entry);
        expect(decoded.payments.single.paymentMethod, method);
      }
      expect(FinancialEntry.tryDecode(f.entry().encoded), isNotNull);
      expect(validFinancialPaymentMethod('credit', 0), false);
      expect(validFinancialPaymentMethod('credit', 121), false);
      expect(validFinancialPaymentMethod('debit', 3), false);
      expect(validFinancialPaymentMethod('other', null), false);
    },
  );
  testWidgets('credit expense validates and saves its installment count', (
    tester,
  ) async {
    NoteDraft? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showFinancialEntryEditor(
                context: context,
                list: f.list(),
                author: 'QA',
                note: f.note(f.entry()),
                onSave: (draft) async {
                  saved = draft;
                },
              ),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Crédito'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crédito'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('payment-installments')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('payment-installments')),
      '6',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('financial-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('financial-save')));
    await tester.pumpAndSettle();
    final entry = FinancialEntry.tryDecode(saved!.financialData)!;
    expect(entry.paymentMethod, 'credit');
    expect(entry.installments, 6);
    expect(tester.takeException(), isNull);
  });
  testWidgets('payment keeps its own method and installments', (tester) async {
    NoteDraft? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showFinancialEntryEditor(
                context: context,
                list: f.list(),
                author: 'QA',
                note: f.note(f.entry()),
                onSave: (draft) async {
                  saved = draft;
                },
              ),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('financial-add-payment')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('financial-add-payment')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('payment-amount')),
      '1000',
    );
    final credit = find.descendant(
      of: find.byType(FinancialDialog),
      matching: find.text('Crédito'),
    );
    await tester.ensureVisible(credit);
    await tester.pumpAndSettle();
    await tester.tap(credit);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('payment-installments')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('payment-installments')),
      '3',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('payment-save')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('financial-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('financial-save')));
    await tester.pumpAndSettle();
    final entry = FinancialEntry.tryDecode(saved!.financialData)!;
    expect(entry.payments.single.paymentMethod, 'credit');
    expect(entry.payments.single.installments, 3);
    expect(entry.paymentMethod, isNull);
    expect(tester.takeException(), isNull);
  });
}
