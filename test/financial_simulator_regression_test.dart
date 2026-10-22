import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nocknock/app/nocknock_app.dart';
import 'package:nocknock/core/theme/app_theme.dart';
import 'package:nocknock/features/auth/data/auth_repository.dart';
import 'package:nocknock/features/auth/domain/app_user.dart';
import 'package:nocknock/features/finance/financial_budget_dialog.dart';
import 'package:nocknock/features/finance/financial_entry.dart';
import 'package:nocknock/features/finance/financial_entry_editor.dart';
import 'package:nocknock/features/finance/financial_list_board.dart';
import 'package:nocknock/features/finance/list_configuration.dart';
import 'package:nocknock/features/notes/data/local_notes_repository.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/logic/notes_cubit.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_version_preview.dart';
import 'package:shared_preferences/shared_preferences.dart';

FinancialEntry money({
  String currency = 'USD',
  String status = 'pending',
  int paid = 325,
}) => FinancialEntry(
  amountMinor: 1050,
  currency: currency,
  counterparty: 'Luis',
  date: DateTime(2026, 10, 22),
  status: status,
  payments: paid == 0
      ? const []
      : [
          FinancialPayment(
            id: 'abono',
            amountMinor: paid,
            date: DateTime(2026, 10, 22),
          ),
        ],
);
Note record(FinancialEntry data) => Note(
  id: 'qa',
  boardId: 'list',
  title: 'Cotización o cobro',
  content: '',
  color: NoteColor.green,
  authorName: 'QA',
  isCompleted: false,
  positionX: 0,
  positionY: 0,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  financialData: data.encoded,
);
NoteList list(NoteListType type) => NoteList(
  id: 'list',
  name: 'QA',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  configuration: ListConfiguration(type: type, currency: 'USD'),
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('es'));
  setUp(() => SharedPreferences.setMockInitialValues({}));
  void compact(WidgetTester tester) {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('all list currencies fit the actual iPhone SE dialog width', (
    tester,
  ) async {
    compact(tester);
    await tester.pumpWidget(
      NockNockApp(repository: LocalNotesRepository(), authRepository: _Guest()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('appbar-menu-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-list-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('list-template')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cobros pendientes').last);
    await tester.pumpAndSettle();
    for (final label in [
      'USD · Dólar estadounidense',
      'EUR · Euro',
      'CLP · Peso chileno',
    ]) {
      await tester.ensureVisible(
        find.byKey(const ValueKey('list-currency-field')),
      );
      await tester.tap(find.byKey(const ValueKey('list-currency-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  for (final dark in [false, true]) {
    testWidgets(
      'budget actions remain accessible with an iPhone SE keyboard, dark=$dark',
      (tester) async {
        compact(tester);
        addTearDown(tester.view.resetViewInsets);
        NoteDraft? saved;
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            home: Scaffold(
              body: Builder(
                builder: (context) => FilledButton(
                  onPressed: () => showFinancialBudgetDialog(
                    context,
                    currency: 'USD',
                    notes: [],
                    save: (d, _) async => saved = d,
                  ),
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Abrir'));
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const ValueKey('budget-amount')));
        await tester.enterText(
          find.byKey(const ValueKey('budget-amount')),
          '10,50',
        );
        await tester.pumpAndSettle();
        expect(
          tester.getBottomLeft(find.widgetWithText(FilledButton, 'Guardar')).dy,
          lessThan(367),
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
        await tester.pumpAndSettle();
        expect(
          FinancialEntry.tryDecode(saved!.financialData)!.amountMinor,
          1050,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'compact quotations expose price and terms without horizontal table checkboxes',
    (tester) async {
      compact(tester);
      final quote = record(money(paid: 0));
      Note? opened;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              child: FinancialListBoard(
                list: list(NoteListType.quotations),
                notes: [quote],
                onEdit: (n) => opened = n,
                onAdd: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DataTable), findsNothing);
      expect(find.byKey(const ValueKey('quote-comparison-qa')), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('quote-comparison-qa')),
      );
      await tester.tap(find.byKey(const ValueKey('quote-comparison-qa')));
      await tester.pumpAndSettle();
      expect(opened, quote);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'history formats payments in currency units instead of displaying cents',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: NoteVersionPreview(note: record(money()))),
        ),
      );
      expect(
        find.text('Abonado: 3,25\u00a0USD · Saldo: 7,25\u00a0USD'),
        findsOneWidget,
      );
      expect(find.textContaining('325 USD'), findsNothing);
    },
  );
  testWidgets(
    'paid entries cannot schedule alerts or add payments beyond the balance',
    (tester) async {
      compact(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showFinancialEntryEditor(
                  context: context,
                  list: list(NoteListType.receivables),
                  author: 'QA',
                  note: record(money(status: 'paid', paid: 1050)),
                  onSave: (_) async {},
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(
        find.text('Sin alertas: el registro está cerrado'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('financial-add-payment')),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'restoring a closed financial version clears the current alert',
    () async {
      final repository = LocalNotesRepository();
      final created = await repository.createTypedList(
        'Cobros',
        const ListConfiguration(type: NoteListType.receivables),
      );
      final cubit = NotesCubit(repository);
      await cubit.load();
      final paid = await repository.createNote(
        created.id,
        NoteDraft(
          title: 'Deuda',
          content: '',
          color: NoteColor.green,
          authorName: 'QA',
          financialData: money(status: 'paid', paid: 1050).encoded,
        ),
      );
      final pending = await repository.updateNote(paid.id, {
        'title': 'Deuda pendiente',
        'financialData': money().encoded,
        'reminderAt': DateTime(2027, 1, 1, 9).toIso8601String(),
      });
      final previous = (await repository.fetchNoteHistory(paid.id)).first;
      await cubit.restoreNoteVersion(pending, previous);
      final restored = (await repository.fetchNotes(created.id)).single;
      expect(restored.financialEntry!.status, 'paid');
      expect(restored.reminderAt, isNull);
      await cubit.close();
      repository.dispose();
    },
  );
}

class _Guest implements AuthRepository {
  @override
  AppUser? get currentUser => null;
  @override
  Stream<AppUser?> get authStateChanges => const Stream.empty();
  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async => null;
  @override
  Future<void> signInWithGoogle() async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<void> deleteAccount() async {}
}
