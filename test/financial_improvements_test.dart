import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nocknock/features/finance/financial_entry.dart';
import 'package:nocknock/features/finance/financial_entry_editor.dart';
import 'package:nocknock/features/finance/financial_export.dart';
import 'package:nocknock/features/finance/financial_list_board.dart';
import 'package:nocknock/features/finance/financial_reports.dart';
import 'package:nocknock/features/finance/financial_budget_dialog.dart';
import 'package:nocknock/features/finance/list_configuration.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/data/local_notes_repository.dart';
import 'package:nocknock/features/notes/logic/notes_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

FinancialPayment payment(int amount, {String id = 'p1'}) => FinancialPayment(
  id: id,
  amountMinor: amount,
  date: DateTime(2026, 10, 21),
  detail: 'Transferencia',
);
FinancialEntry entry({
  int amount = 10001,
  String currency = 'CLP',
  String status = 'pending',
  List<FinancialPayment> payments = const [],
  List<String> people = const [],
  String payer = '',
  String kind = 'entry',
  String period = 'all',
  DateTime? date,
}) => FinancialEntry(
  amountMinor: amount,
  currency: currency,
  counterparty: 'María',
  date: date ?? DateTime(2026, 10, 20),
  status: status,
  payments: payments,
  participants: people,
  paidBy: payer,
  kind: kind,
  period: period,
  dueDate: DateTime(2026, 10, 22),
);
Note note(FinancialEntry e, {String id = 'n', String title = 'Compra'}) => Note(
  id: id,
  boardId: 'list',
  title: title,
  content: 'Detalle',
  color: NoteColor.green,
  category: NoteCategory.finance,
  authorName: 'Ana',
  isCompleted: false,
  positionX: 0,
  positionY: 0,
  createdAt: DateTime(2026, 10, 20),
  updatedAt: DateTime(2026, 10, 20),
  financialData: e.encoded,
);
NoteList list({NoteListType type = NoteListType.expenses}) => NoteList(
  id: 'list',
  name: 'Gastos de María',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  configuration: ListConfiguration(type: type),
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('es'));
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'partial payments preserve exact balance, dates and receipt association',
    () {
      final e = entry(
        payments: [
          FinancialPayment(
            id: 'p',
            amountMinor: 4000,
            date: DateTime(2026, 10, 21),
            detail: 'Abono',
            receiptId: 'receipt',
          ),
        ],
      );
      final decoded = FinancialEntry.tryDecode(e.encoded)!;
      expect(decoded, e);
      expect(decoded.paidMinor, 4000);
      expect(decoded.balanceMinor, 6001);
      expect(decoded.isOverdue(DateTime(2026, 10, 22, 23)), false);
      expect(decoded.isOverdue(DateTime(2026, 10, 23)), true);
      expect(entry(status: 'paid').isOverdue(DateTime(2027)), false);
    },
  );
  test('invalid overpayments, duplicate payment IDs, false paid states and invalid dates are rejected', () {
    for (final e in [
      entry(payments: [payment(10002)]),
      entry(payments: [payment(1), payment(2)]),
      entry(payments: [payment(1)], status: 'paid'),
      entry(people: ['Ana', 'Ana'], payer: 'Ana'),
    ]) {
      expect(FinancialEntry.tryDecode(e.encoded), isNull);
    }
    final raw = jsonDecode(entry().encoded) as Map<String, dynamic>;
    raw['dueDate'] = '2026-02-30';
    expect(FinancialEntry.tryDecode(jsonEncode(raw)), isNull);
  });
  test(
    'old version one records remain readable and retain legacy due dates',
    () {
      final raw = jsonDecode(entry().encoded) as Map<String, dynamic>;
      raw.removeWhere(
        (k, v) => ![
          'version',
          'amountMinor',
          'currency',
          'counterparty',
          'date',
          'status',
        ].contains(k),
      );
      raw['version'] = 1;
      final e = FinancialEntry.tryDecode(jsonEncode(raw))!;
      expect(e.effectiveDueDate(receivable: true), e.date);
      expect(e.effectiveDueDate(), isNull);
      expect(
        entry().effectiveDueDate(receivable: true),
        DateTime(2026, 10, 22),
      );
    },
  );
  test(
    'budgets never inflate totals; partial payments split pending and paid',
    () {
      final totals = financialTotals([
        note(entry(payments: [payment(4000)])),
        note(entry(amount: 2000, status: 'paid'), id: '2'),
        note(entry(amount: 90000, kind: 'budget'), id: 'b'),
        note(entry(amount: 200, currency: 'USD'), id: '3'),
      ]);
      expect(totals['CLP']!['total'], 12001);
      expect(totals['CLP']!['pending'], 6001);
      expect(totals['CLP']!['paid'], 6000);
      expect(totals['USD']!['total'], 200);
    },
  );
  test('monthly budgets and summaries use all records in the correct currency and month', () {
    final notes = [
      note(entry(amount: 100)),
      note(entry(amount: 200, date: DateTime(2026, 9, 1)), id: '2'),
      note(entry(amount: 300, status: 'rejected'), id: '3'),
      note(entry(amount: 400, currency: 'USD'), id: '4'),
    ];
    expect(budgetSpent(notes, entry(kind: 'budget', period: '2026-10')), 100);
    expect(budgetSpent(notes, entry(kind: 'budget')), 300);
    expect(financialRecords(notes, month: '2026-09').single.id, '2');
  });
  test(
    'shared expense rounding conserves every cent and currencies stay separate',
    () {
      final e = entry(
        amount: 100,
        currency: 'USD',
        people: ['Ana', 'María', 'Pedro'],
        payer: 'Ana',
        status: 'paid',
      );
      expect(e.shares, {'Ana': 34, 'María': 33, 'Pedro': 33});
      final notes = [
        note(e),
        note(
          entry(
            amount: 10,
            people: ['Ana', 'Pedro'],
            payer: 'Pedro',
            status: 'paid',
          ),
          id: '2',
        ),
      ];
      final balances = sharedBalances(notes);
      expect(balances['USD'], {'Ana': 66, 'María': -33, 'Pedro': -33});
      expect(balances['CLP'], {'Pedro': 5, 'Ana': -5});
      for (final b in balances.values) {
        expect(b.values.fold<int>(0, (s, v) => s + v), 0);
      }
      expect(sharedTransfers(notes).length, 3);
    },
  );
  test('recorded transfers settle shared debts without inflating spending', () {
    final purchase = note(
      entry(
        amount: 100,
        people: ['Ana', 'María'],
        payer: 'Ana',
        status: 'paid',
      ),
    );
    final transfer = note(
      entry(amount: 50, kind: 'settlement', payer: 'María', status: 'paid'),
      id: 't',
    );
    // Receiver differs from the default counterparty of this helper.
    final raw = jsonDecode(transfer.financialData!) as Map<String, dynamic>;
    raw['counterparty'] = 'Ana';
    final settled = Note.fromJson({
      ...transfer.toJson(),
      'financialData': jsonEncode(raw),
    });
    expect(sharedTransfers([purchase, settled]), isEmpty);
    expect(financialTotals([purchase, settled])['CLP']!['total'], 100);
    expect(budgetSpent([purchase, settled], entry(kind: 'budget')), 100);
  });
  test('Excel contains numeric amounts, separate payment/repartition sheets and literal formula-like text', () {
    final bytes = financialExcel([
      note(
        entry(payments: [payment(4000)]),
        title: '=HYPERLINK("bad") & <Compra>',
      ),
    ]);
    final archive = ZipDecoder().decodeBytes(bytes);
    final xml = utf8.decode(
      archive.findFile('xl/worksheets/sheet1.xml')!.content as List<int>,
    );
    expect(xml, contains('&amp; &lt;Compra&gt;'));
    expect(xml, contains('=HYPERLINK'));
    expect(xml, contains('<v>10001</v>'));
    expect(xml, isNot(contains('<f>')));
    expect(archive.findFile('xl/worksheets/sheet2.xml'), isNotNull);
    expect(archive.findFile('xl/worksheets/sheet3.xml'), isNotNull);
  });
  test('PDF export handles Spanish and multipage reports offline', () async {
    final notes = List.generate(
      100,
      (i) => note(entry(), id: '$i', title: 'Cotización María $i'),
    );
    final bytes = await financialPdf(list(), notes, month: '2026-10');
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    expect(bytes.length, greaterThan(10000));
    if (Platform.environment['FINANCE_EXPORT_QA'] == '1') {
      await File('/tmp/nocknock-finance-report.pdf').writeAsBytes(bytes);
      await File('/tmp/nocknock-finance-report.xlsx')
          .writeAsBytes(financialExcel(notes));
    }
  });
  test('new finance fields persist through restart, history and cubit reminder updates', () async {
    final repo = LocalNotesRepository();
    final createdList = await repo.createTypedList(
      'Gastos',
      const ListConfiguration(type: NoteListType.expenses),
    );
    final cubit = NotesCubit(repo);
    await cubit.load();
    final draft = NoteDraft(
      title: 'Compra',
      content: '',
      color: NoteColor.green,
      authorName: 'Ana',
      financialData: entry(payments: [payment(500)]).encoded,
      reminderAt: DateTime(2027, 1, 1, 9),
    );
    await cubit.saveFinancialEntry(createdList.id, draft);
    var saved = (await repo.fetchNotes(createdList.id)).single;
    expect(saved.financialEntry!.balanceMinor, 9501);
    final changed = NoteDraft(
      title: 'Compra',
      content: '',
      color: NoteColor.green,
      authorName: 'Ana',
      financialData: entry(status: 'paid').encoded,
    );
    await cubit.saveFinancialEntry(createdList.id, changed, existing: saved);
    saved = (await repo.fetchNotes(createdList.id)).single;
    expect(saved.reminderAt, isNull);
    expect(
      (await repo.fetchNoteHistory(saved.id))
          .first
          .note
          .financialEntry!
          .payments
          .single
          .amountMinor,
      500,
    );
    await cubit.close();
    repo.dispose();
    final reopened = LocalNotesRepository();
    expect(
      (await reopened.fetchNotes(createdList.id)).single.financialEntry!.status,
      'paid',
    );
    reopened.dispose();
  });
  testWidgets(
    'payment editor saves partial balance and preserves a due-date alert',
    (tester) async {
      NoteDraft? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showFinancialEntryEditor(
                  context: context,
                  list: list(),
                  author: 'Ana',
                  note: note(entry()),
                  onSave: (draft) async => saved = draft,
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
      await tester.tap(find.byKey(const ValueKey('financial-add-payment')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('payment-amount')),
        '4000',
      );
      await tester.tap(find.byKey(const ValueKey('payment-save')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('financial-save')));
      await tester.tap(find.byKey(const ValueKey('financial-save')));
      await tester.pumpAndSettle();
      expect(
        FinancialEntry.tryDecode(saved!.financialData)!.balanceMinor,
        6001,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'budget dialog saves encrypted-transport-compatible metadata without creating an expense',
    (tester) async {
      NoteDraft? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showFinancialBudgetDialog(
                  context,
                  currency: 'CLP',
                  notes: [],
                  save: (draft, _) async => saved = draft,
                  month: '2026-10',
                ),
                child: const Text('Presupuesto'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Presupuesto'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('budget-amount')),
        '30000',
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(FinancialEntry.tryDecode(saved!.financialData)!.kind, 'budget');
      expect(FinancialEntry.tryDecode(saved!.financialData)!.period, '2026-10');
    },
  );
  testWidgets('financial board shows comparison and handles month filtering', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FinancialListBoard(
              list: list(type: NoteListType.quotations),
              notes: [note(entry(), title: 'Trabajo')],
              onEdit: (_) {},
              onAdd: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('Comparar cotizaciones'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('financial-month')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('octubre 2026').last);
    await tester.pumpAndSettle();
    expect(find.text('Resumen de registros del mes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
