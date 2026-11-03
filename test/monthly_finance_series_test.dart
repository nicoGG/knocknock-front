import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/finance/monthly_finance_series.dart';
import 'package:nocknock/features/finance/list_configuration.dart';
import 'package:nocknock/features/notes/data/local_notes_repository.dart';
import 'package:nocknock/features/notes/data/note_search.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/material.dart';
import 'package:nocknock/features/finance/monthly_finance_page.dart';
import 'package:nocknock/features/notes/data/list_protection_controller.dart';
import 'package:nocknock/features/notes/logic/notes_cubit.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'create and stop a monthly series through its form; ledger remains available',
    (tester) async {
      final repo = LocalNotesRepository();
      final list = await repo.createTypedList(
        'Clientes',
        const ListConfiguration(
          type: NoteListType.receivables,
          currency: 'USD',
        ),
      );
      final cubit = NotesCubit(repo);
      await tester.runAsync(cubit.load);
      await cubit.selectList(list.id);
      final protection = ListProtectionController();
      await tester.pumpWidget(
        MaterialApp(
          home: MonthlyFinancePage(
            list: list,
            cubit: cubit,
            protection: protection,
            author: 'Ana',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nuevo cobro mensual'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Suscripción');
      await tester.enterText(fields.at(1), '10,50');
      await tester.enterText(fields.at(2), 'Cliente');
      tester.testTextInput.hide();
      await tester.ensureVisible(find.text('Crear serie'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Crear serie'));
      await tester.pumpAndSettle();
      expect(cubit.state.notes.length, 2);
      expect(cubit.state.notes.map((n) => n.financialEntry!.balanceMinor), [
        1050,
        1050,
      ]);
      final stop = find.byTooltip('Detener serie');
      await tester.ensureVisible(stop);
      await tester.pumpAndSettle();
      await tester.tap(stop);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Detener serie'));
      await tester.pumpAndSettle();
      expect(await cubit.monthlyRules(list.id), isEmpty);
      expect(await repo.fetchNotes(list.id), hasLength(2));
      await tester.pumpWidget(const SizedBox());
      protection.dispose();
      await tester.runAsync(cubit.close);
    },
  );
  for (final type in [NoteListType.expenses, NoteListType.receivables]) {
    test(
      '${type.name}: separate month-end records keep payments and receipts through edits, deletion, catch-up and stopping',
      () async {
        final repo = LocalNotesRepository();
        final board = await repo.createTypedList(
          'Casa',
          ListConfiguration(type: type),
        );
        final rule = MonthlyFinanceRule(
          start: DateTime(2028, 1, 31),
          amount: 15000,
          currency: 'CLP',
          counterparty: 'Ana',
        );
        final template = await repo.createNote(
          board.id,
          NoteDraft(
            title: 'Arriendo',
            content: '',
            financialData: rule.encode(),
            color: NoteColor.green,
            authorName: 'Ana',
          ),
        );
        expect(noteMatchesQuery(template, 'arriendo'), isFalse);
        final service = MonthlyFinanceSeries(repo);
        final results = await Future.wait([
          service.load(board.id, now: DateTime(2028, 1, 1)),
          MonthlyFinanceSeries(repo).load(board.id, now: DateTime(2028, 1, 1)),
        ]);
        final months = results.first
          ..sort(
            (a, b) => a.financialEntry!.date.compareTo(b.financialEntry!.date),
          );
        expect(months.length, 2);
        expect(months.map((n) => n.financialEntry!.dueDate), [
          DateTime(2028, 1, 31),
          DateTime(2028, 2, 29),
        ]);
        expect(
          results.last.map((n) => n.id).toSet(),
          months.map((n) => n.id).toSet(),
        );
        final january = months.first;
        final data = jsonDecode(january.financialData!);
        data['amountMinor'] = 18000;
        data['payments'] = [
          {
            'id': 'abono',
            'amountMinor': 3000,
            'date': '2028-01-31',
            'detail': '',
            'receiptId': 'pdf',
          },
        ];
        await repo.updateNote(january.id, {
          'expectedRevision': january.revision,
          'financialData': jsonEncode(data),
          'attachments': [
            {
              'id': 'pdf',
              'name': 'enero.pdf',
              'sizeBytes': 1,
              'mimeType': 'application/pdf',
              'dataBase64': 'YQ==',
            },
          ],
        });
        await repo.deleteNote(months.last.id);
        final fresh = LocalNotesRepository();
        final catchup = await MonthlyFinanceSeries(fresh)
            .load(board.id, now: DateTime(2028, 4, 1));
        expect(catchup.map((n) => n.financialEntry!.date.month).toSet(), {
          1,
          3,
          4,
          5,
        });
        final edited = catchup.singleWhere((n) => n.id == january.id);
        expect(edited.financialEntry!.paidMinor, 3000);
        expect(edited.photoAttachments.single.name, 'enero.pdf');
        for (final n in catchup.where((n) => n.id != january.id)) {
          expect(n.financialEntry!.amountMinor, 15000);
          expect(n.financialEntry!.payments, isEmpty);
          expect(n.photoAttachments, isEmpty);
        }
        final latest = (await fresh.fetchNotes(board.id))
            .singleWhere((n) => n.id == template.id);
        await fresh.deleteNote(template.id, expectedRevision: latest.revision);
        expect(
          (await MonthlyFinanceSeries(
            fresh,
          ).load(board.id, now: DateTime(2029, 1))).length,
          4,
        );
        fresh.dispose();
        repo.dispose();
      },
    );
  }
}
