import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/finance/financial_entry.dart';
import 'package:nocknock/features/finance/financial_entry_editor.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'financial_improvements_test.dart' as fixtures;

import 'package:nocknock/features/finance/financial_export.dart';
import 'package:nocknock/features/finance/financial_installment_preview.dart';
import 'package:nocknock/features/finance/financial_list_board.dart';
import 'package:nocknock/features/finance/financial_reports.dart';
import 'package:nocknock/features/finance/receipt_scanner.dart';
import 'package:nocknock/features/finance/receipt_total.dart';
import 'package:nocknock/features/notes/domain/note.dart';

FinancialEntry purchase({
  int amount = 10001,
  int paid = 0,
  String status = 'pending',
  String currency = 'CLP',
}) => FinancialEntry(
  amountMinor: amount,
  currency: currency,
  counterparty: 'Tienda',
  date: DateTime(2026, 12, 31),
  dueDate: DateTime(2027, 1, 31),
  paymentMethod: 'credit',
  installments: 3,
  status: status,
  payments: [
    if (paid > 0)
      FinancialPayment(
        id: 'p1',
        amountMinor: paid,
        date: DateTime(2027, 1, 31),
      ),
  ],
);
Note record(FinancialEntry entry) => Note(
  id: 'n1',
  boardId: 'b1',
  isCompleted: false,
  positionX: 0,
  positionY: 0,
  title: 'Compra',
  content: '',
  color: NoteColor.green,
  authorName: 'Ana',
  createdAt: entry.date,
  updatedAt: entry.date,
  financialData: entry.encoded,
);

void main() {
  setUpAll(() => initializeDateFormatting('es'));
  testWidgets(
    'editing a partially paid deferred purchase preserves the first quota date',
    (tester) async {
      NoteDraft? saved;
      final original = purchase(paid: 4000);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showFinancialEntryEditor(
                  context: context,
                  list: fixtures.list(),
                  author: 'QA',
                  note: record(original),
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
      await tester.ensureVisible(find.byKey(const ValueKey('financial-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('financial-save')));
      await tester.pumpAndSettle();
      final restored = FinancialEntry.tryDecode(saved!.financialData)!;
      expect(restored.dueDate, original.dueDate);
      expect(
        restored.installmentSchedule.map((i) => i.date),
        original.installmentSchedule.map((i) => i.date),
      );
      expect(restored.paidMinor, 4000);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'installments preserve the total, leap days and the original day anchor',
    () {
      final schedule = financialInstallmentSchedule(
        amountMinor: 10001,
        count: 3,
        firstDate: DateTime(2028, 1, 31),
      );
      expect(schedule.map((i) => i.amountMinor), [3334, 3334, 3333]);
      expect(schedule.map((i) => i.date), [
        DateTime(2028, 1, 31),
        DateTime(2028, 2, 29),
        DateTime(2028, 3, 31),
      ]);
      expect(schedule.fold<int>(0, (s, i) => s + i.amountMinor), 10001);
      expect(
        financialMonthOffset(DateTime(2027, 1, 31), 1),
        DateTime(2027, 2, 28),
      );
    },
  );
  test('monthly records and budgets count each installment once without creating payments', () {
    final e = purchase();
    final n = record(e);
    expect(financialRecords([n], month: '2026-12'), isEmpty);
    expect(financialRecords([n], month: '2027-02'), hasLength(1));
    expect(
      financialTotals([n], month: '2027-02')['CLP'],
      containsPair('total', 3334),
    );
    expect(financialTotals([n])['CLP'], containsPair('total', 10001));
    expect(e.payments, isEmpty);
    expect(e.paidInMonth('2027-02'), 0);
    final budget = FinancialEntry(
      amountMinor: 5000,
      currency: 'CLP',
      counterparty: '',
      date: DateTime(2027),
      kind: 'budget',
      period: '2027-02',
    );
    expect(budgetSpent([n], budget), 3334);
    final restored = FinancialEntry.tryDecode(e.encoded)!;
    expect(restored.installmentSchedule.map((i) => i.amountMinor), [
      3334,
      3334,
      3333,
    ]);
    expect(restored.firstInstallmentDate, DateTime(2027, 1, 31));
  });
  test('partial payments apply to oldest installments and move the effective due date', () {
    final entry = purchase(paid: 4000);
    expect(entry.installmentSchedule.map((i) => i.paidMinor), [3334, 666, 0]);
    expect(entry.balanceInMonth('2027-02'), 2668);
    expect(entry.effectiveDueDate(), DateTime(2027, 2, 28));
    expect(entry.isOverdue(DateTime(2027, 2, 15)), false);
    expect(entry.isOverdue(DateTime(2027, 3)), true);
    expect(
      purchase(status: 'paid').installmentSchedule
          .every((i) => i.balanceMinor == 0),
      true,
    );
    expect(purchase(status: 'rejected').balanceInMonth('2027-02'), 0);
  });
  test('normal records retain their original month and cents are exact', () {
    final e = FinancialEntry(
      amountMinor: 10001,
      currency: 'USD',
      counterparty: '',
      date: DateTime(2026, 10, 23),
    );
    expect(e.amountInMonth('2026-10'), 10001);
    expect(e.amountInMonth('2026-11'), 0);
    expect(
      purchase(currency: 'USD').installmentSchedule.map((i) => i.amountMinor),
      [3334, 3334, 3333],
    );
  });
  test('monthly Excel includes scheduled quotas and period amounts', () {
    final bytes = financialExcel([record(purchase())], month: '2027-02');
    final archive = ZipDecoder().decodeBytes(bytes);
    final workbook = utf8.decode(
      archive.findFile('xl/workbook.xml')!.content as List<int>,
    );
    expect(workbook, contains('Cuotas diferidas'));
    final xml = archive.files
        .where((f) => f.name.startsWith('xl/worksheets/'))
        .map((f) => utf8.decode(f.content as List<int>))
        .join();
    expect(xml, contains('28-02-2027'));
    expect(xml, contains('<v>3334</v>'));
    final quotas = utf8.decode(
      archive.findFile('xl/worksheets/sheet2.xml')!.content as List<int>,
    );
    expect(quotas, isNot(contains('31-01-2027')));
    expect(quotas, contains('2/3'));
  });
  test('receipt totals exclude tax, subtotals, change and item counts', () {
    expect(
      receiptTotalMinor(
        'SUBTOTAL 10.000\nIVA 1.900\nTOTAL \$ 11.900\nEFECTIVO 20.000\nVUELTO 8.100\nTOTAL ARTICULOS 4',
        'CLP',
      ),
      11900,
    );
    expect(
      receiptTotalMinor(
        'SUB TOTAL 10.000\nTOTAL A PAGAR\nCLP 11.900\nRUT 76.123.456-7',
        'CLP',
      ),
      11900,
    );
    expect(receiptTotalMinor('TOTAL 1.234,00', 'CLP'), 1234);
    expect(receiptTotalMinor('TOTAL USD 1,234.56', 'USD'), 123456);
    expect(receiptTotalMinor('MONTO TOTAL EUR 1.234,56', 'EUR'), 123456);
    expect(receiptTotalMinor('TOTAL 12,345', 'CLP'), 12345);
  });
  test('ambiguous or invalid receipt amounts never guess', () {
    for (final text in [
      'IVA 1.900\nSUBTOTAL 10.000',
      'TOTAL 1000\nTOTAL 2000',
      'TOTAL 1.234,56',
      'TOTAL USD 10.00',
      'TOTAL -1000',
      'TOTAL 1.2.3',
      'TOTAL 10.00 20.00',
    ]) {
      expect(receiptTotalMinor(text, 'CLP'), isNull, reason: text);
    }
    expect(receiptTotalMinor('TOTAL 1000\nTOTAL A PAGAR 2000', 'CLP'), 2000);
  });
  testWidgets('schedule updates when amount and installment count change', (
    tester,
  ) async {
    final amount = TextEditingController(text: '10.001');
    final count = TextEditingController(text: '3');
    addTearDown(amount.dispose);
    addTearDown(count.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FinancialInstallmentPreview(
              amount: amount,
              installments: count,
              currency: 'CLP',
              firstDate: DateTime(2027, 1, 31),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pago diferido · 3 cuotas mensuales'));
    await tester.pumpAndSettle();
    expect(find.text('Cuota 2 de 3 · 28-02-2027'), findsOneWidget);
    amount.text = '12.000';
    count.text = '2';
    await tester.pumpAndSettle();
    expect(find.text('Pago diferido · 2 cuotas mensuales'), findsOneWidget);
    expect(find.text('Cuota 3 de 3 · 31-03-2027'), findsNothing);
  });
  testWidgets(
    'recognized receipt total is only returned after the user chooses it',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('cl.nocknock/receipt_scanner');
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => 'TOTAL CLP 15.990',
      );
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      int? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  chosen = await suggestReceiptTotal(
                    context,
                    NoteAttachment(
                      id: 'r',
                      name: 'Boleta.jpg',
                      mimeType: 'image/jpeg',
                      sizeBytes: 3,
                      dataBase64: base64Encode([1, 2, 3]),
                    ),
                    'CLP',
                  );
                },
                child: const Text('Leer'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Leer'));
      await tester.pumpAndSettle();
      expect(chosen, isNull);
      expect(find.text('Total detectado'), findsOneWidget);
      await tester.tap(find.text('Usar total'));
      await tester.pumpAndSettle();
      expect(chosen, 15990);
    },
  );
}
