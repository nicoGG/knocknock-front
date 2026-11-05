import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:nocknock/core/theme/app_theme.dart';
import 'package:nocknock/features/personal_expenses/expense_style.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nocknock/features/finance/financial_agenda.dart';
import 'package:nocknock/features/finance/financial_agenda_page.dart';
import 'package:nocknock/features/finance/financial_entry.dart';
import 'package:nocknock/features/finance/list_configuration.dart';
import 'package:nocknock/features/notes/data/list_protection_controller.dart';
import 'package:nocknock/features/notes/data/local_notes_repository.dart';
import 'package:nocknock/features/notes/data/notes_repository.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/logic/notes_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final first = DateTime(2026, 12, 31);
  NoteDraft draft(String title, FinancialEntry entry) => NoteDraft(
    title: title,
    content: '',
    color: NoteColor.green,
    authorName: 'Ana',
    financialData: entry.encoded,
  );
  test('only outstanding installments fall into each calendar week, preserving the last peso', () async {
    final repo = LocalNotesRepository();
    final list = await repo.createTypedList(
      'Casa',
      const ListConfiguration(type: NoteListType.expenses),
    );
    final entry = FinancialEntry(
      amountMinor: 10001,
      currency: 'CLP',
      counterparty: 'Tienda',
      date: first,
      dueDate: first,
      paymentMethod: 'credit',
      installments: 3,
      payments: [FinancialPayment(id: 'p', amountMinor: 3500, date: first)],
    );
    final note = await repo.createNote(list.id, draft('Compra', entry));
    final dues = agendaDues([NoteSearchResult(note: note, list: list)]);
    expect(dues.map((d) => d.date), [
      DateTime(2027, 1, 31),
      DateTime(2027, 2, 28),
    ]);
    expect(dues.map((d) => d.balance), [3168, 3333]);
    expect(dues.map((d) => d.firstUnpaid), [true, false]);
    expect(
      AgendaPeriod.week.includes(dues.first.date, DateTime(2027, 1, 25)),
      isTrue,
    );
    expect(
      AgendaPeriod.nextWeek.includes(dues.first.date, DateTime(2027, 1, 24)),
      isTrue,
    );
    expect(
      AgendaPeriod.overdue.includes(dues.first.date, DateTime(2027, 2, 1)),
      isTrue,
    );
    repo.dispose();
  });

  testWidgets(
    'agenda combines currencies, hides locked lists and posts the abono to its source',
    (tester) async {
      final repo = LocalNotesRepository();
      final now = DateTime.now();
      final expenses = await repo.createTypedList(
        'Casa',
        const ListConfiguration(type: NoteListType.expenses),
      );
      final cobros = await repo.createTypedList(
        'Clientes',
        const ListConfiguration(
          type: NoteListType.receivables,
          currency: 'USD',
        ),
      );
      final hidden = await repo.createTypedList(
        'Privada',
        const ListConfiguration(type: NoteListType.expenses),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('protected_note_list_ids_v1', [hidden.id]);
      final protection = ListProtectionController(preferences: prefs);
      final expense = FinancialEntry(
        amountMinor: 15000,
        currency: 'CLP',
        counterparty: 'Servicios',
        date: now,
        dueDate: now,
      );
      await repo.createNote(expenses.id, draft('Agua', expense));
      await repo.createNote(hidden.id, draft('Secreto', expense));
      // v1 receivables used the transaction date as their deadline.
      final legacy = jsonDecode(
        FinancialEntry(
          amountMinor: 1050,
          currency: 'USD',
          counterparty: 'Ana',
          date: now,
        ).encoded,
      ) as Map<String, dynamic>;
      legacy['version'] = 1;
      final bill = await repo.createNote(
        cobros.id,
        NoteDraft(
          title: 'Servicio',
          content: '',
          color: NoteColor.green,
          authorName: 'Ana',
          reminderAt: now.add(const Duration(days: 1)),
          financialData: jsonEncode(legacy),
        ),
      );
      final cubit = NotesCubit(repo);
      await tester.runAsync(cubit.load);
      await tester.pumpWidget(
        MaterialApp(
          home: FinancialAgendaPage(cubit: cubit, protection: protection),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('CLP'), findsOneWidget);
      expect(find.text('USD'), findsOneWidget);
      expect(find.text('Secreto'), findsNothing);
      Future<void> pay(String amount) async {
        final row = find.ancestor(
          of: find.text('Servicio'),
          matching: find.byType(ExpenseSurface),
        );
        final button = find.descendant(
          of: row,
          matching: find.text('Registrar abono'),
        );
        await tester.scrollUntilVisible(
          button,
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('payment-amount')),
          amount,
        );
        final save = find.byKey(const ValueKey('payment-save'));
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        await tester.tap(save);
        await tester.pumpAndSettle();
      }

      await pay('3,25');
      final partial = (await repo.fetchNotes(cobros.id)).single;
      expect(partial.financialEntry!.balanceMinor, 725);
      expect(
        partial.financialEntry!.dueDate,
        DateTime(now.year, now.month, now.day),
      );
      expect(partial.reminderAt, isNotNull);
      await expectLater(
        cubit.recordAgendaPayment(
          NoteSearchResult(note: bill, list: cobros),
          FinancialPayment(id: 'stale', amountMinor: 100, date: now),
          [],
        ),
        throwsA(isA<NotesPersistenceFailure>()),
      );
      await pay('7,25');
      final closed = (await repo.fetchNotes(cobros.id)).single;
      expect(closed.financialEntry!.status, 'paid');
      expect(closed.financialEntry!.payments.length, 2);
      expect(closed.reminderAt, isNull);
      expect(find.text('Servicio'), findsNothing);
      expect(
        (await repo.fetchNotes(expenses.id))
            .single
            .financialEntry!
            .balanceMinor,
        15000,
      );
      await tester.pumpWidget(const SizedBox());
      protection.dispose();
      await tester.runAsync(cubit.close);
    },
  );
  for (final dark in [true, false]) {
    testWidgets('empty agenda adapts to theme, filters and large text: $dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final font = FontLoader('Avenir')
        ..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'));
      await font.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      final repo = LocalNotesRepository();
      final cubit = NotesCubit(repo);
      await tester.runAsync(cubit.load);
      final protection = ListProtectionController(
        preferences: await SharedPreferences.getInstance(),
      );
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          home: RepaintBoundary(
            key: key,
            child: FinancialAgendaPage(cubit: cubit, protection: protection),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tu semana, sin pendientes'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (Platform.environment['AGENDA_SCREENSHOT'] case final path?) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$path-${dark ? 'dark' : 'light'}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      tester.view.physicalSize = const Size(320, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Vencidos'));
      await tester.tap(find.text('Vencidos'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Sin vencimientos atrasados'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Sin vencimientos atrasados'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      protection.dispose();
      await tester.runAsync(cubit.close);
    });
  }
}
