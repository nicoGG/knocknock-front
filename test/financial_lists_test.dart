import 'package:nocknock/features/finance/financial_style.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nocknock/app/nocknock_app.dart';
import 'package:nocknock/features/auth/data/auth_repository.dart';
import 'package:nocknock/features/auth/domain/app_user.dart';
import 'package:nocknock/features/finance/financial_entry.dart';
import 'package:nocknock/features/finance/financial_list_board.dart';
import 'package:nocknock/features/finance/financial_entry_editor.dart';
import 'package:nocknock/features/finance/list_configuration.dart';
import 'package:nocknock/features/notes/data/local_notes_repository.dart';
import 'package:nocknock/features/notes/data/notes_repository.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/logic/notes_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

FinancialEntry entry(
  int amount, {
  String currency = 'CLP',
  String status = 'pending',
}) => FinancialEntry(
  amountMinor: amount,
  currency: currency,
  counterparty: 'Ana',
  date: DateTime(2026, 10, 22),
  status: status,
);
NoteDraft draft(
  FinancialEntry value, {
  List<NoteAttachment> attachments = const [],
}) => NoteDraft(
  title: 'Materiales',
  content: 'Boleta',
  color: NoteColor.green,
  authorName: 'Nico',
  financialData: value.encoded,
  attachments: attachments,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('es'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'amount parsing uses integer units and refuses ambiguous or invalid input',
    () {
      expect(FinancialEntry.parseAmount('15000', 'CLP'), 15000);
      expect(FinancialEntry.parseAmount('123,45', 'USD'), 12345);
      expect(FinancialEntry.parseAmount('123.4', 'EUR'), 12340);
      for (final text in [
        '0',
        '-1',
        '1.234,50',
        'foo',
        '10.123',
        '99999999999999999',
      ]) {
        expect(FinancialEntry.parseAmount(text, 'USD'), isNull);
      }
      expect(FinancialEntry.parseAmount('15.000', 'CLP'), isNull);
      expect(FinancialEntry.tryDecode(entry(100).encoded), entry(100));
      expect(
        FinancialEntry.tryDecode(
          entry(100).encoded.replaceAll('2026-10-22', '2026-02-30'),
        ),
        isNull,
      );
    },
  );

  test('existing list JSON defaults to Normal and new custom lists survive restart', () async {
    final now = DateTime.now().toIso8601String();
    expect(
      NoteList.fromJson({
        'id': 'old',
        'name': 'Normal',
        'createdAt': now,
        'updatedAt': now,
      }).configuration.type,
      NoteListType.normal,
    );
    final repository = LocalNotesRepository();
    final list = await repository.createTypedList(
      'Viaje',
      const ListConfiguration(
        type: NoteListType.custom,
        customTypeName: 'Fondo de viaje',
        currency: 'EUR',
      ),
    );
    repository.dispose();
    final reopened = LocalNotesRepository();
    final restored = (await reopened.fetchLists()).singleWhere(
      (value) => value.id == list.id,
    );
    expect(restored.configuration.label, 'Fondo de viaje');
    expect(restored.configuration.currency, 'EUR');
    reopened.dispose();
  });

  test('totals separate currencies and statuses and retain receipt data through edits and restore', () async {
    final repository = LocalNotesRepository();
    final list = await repository.createTypedList(
      'Gastos',
      const ListConfiguration(type: NoteListType.expenses),
    );
    final pdf = NoteAttachment(
      id: 'receipt',
      name: 'Boleta.pdf',
      mimeType: 'application/pdf',
      sizeBytes: 8,
      dataBase64: base64Encode(utf8.encode('%PDF-1.4')),
    );
    final first = await repository.createNote(
      list.id,
      draft(entry(1000), attachments: [pdf]),
    );
    await repository.createNote(list.id, draft(entry(2000, status: 'paid')));
    await repository.createNote(list.id, draft(entry(12345, currency: 'USD')));
    await repository.createNote(
      list.id,
      const NoteDraft(
        title: 'Nota antigua sin monto',
        content: '',
        color: NoteColor.none,
        authorName: 'Nico',
      ),
    );
    var totals = financialTotals(await repository.fetchNotes(list.id));
    expect(totals['CLP'], containsPair('total', 3000));
    expect(totals['CLP'], containsPair('pending', 1000));
    expect(totals['USD'], containsPair('total', 12345));
    final updated = await repository.updateNote(first.id, {
      'financialData': entry(1500).encoded,
    });
    expect(updated.photoAttachments.single.dataBase64, pdf.dataBase64);
    expect(
      (await repository.fetchNoteHistory(first.id))
          .single
          .note
          .financialEntry
          ?.amountMinor,
      1000,
    );
    await repository.deleteNote(first.id);
    expect(
      financialTotals(await repository.fetchNotes(list.id))['CLP']!['total'],
      2000,
    );
    await repository.restoreNote(first.id);
    totals = financialTotals(await repository.fetchNotes(list.id));
    expect(totals['CLP']!['total'], 3500);
    repository.dispose();
  });

  test(
    'financial lists load all records instead of summing a first page of forty',
    () async {
      final repository = _PagedLocal();
      final list = await repository.createTypedList(
        'Gastos',
        const ListConfiguration(type: NoteListType.expenses),
      );
      for (var i = 0; i < 51; i++) {
        await repository.createNote(list.id, draft(entry(100)));
      }
      final cubit = NotesCubit(repository);
      await cubit.load();
      await cubit.selectList(list.id);
      expect(cubit.state.notes, hasLength(51));
      expect(cubit.state.hasMoreNotes, false);
      expect(financialTotals(cubit.state.notes)['CLP']!['total'], 5100);
      await cubit.close();
    },
  );

  testWidgets(
    'creates an expense list, adds an amount and changes its payment status',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = LocalNotesRepository();
      await tester.pumpWidget(
        NockNockApp(repository: repository, authRepository: _Guest()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('appbar-menu-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-list-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('list-name-field')),
        'Gastos de casa',
      );
      await tester.tap(find.byKey(const ValueKey('list-type-field')));
      await tester.pumpAndSettle();
      expect(
        find.byIcon(FinancialStyle.typeIcon(NoteListType.expenses)),
        findsWidgets,
      );
      await tester.tap(find.text('Gastos').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('create-list-confirm-button')),
      );
      await tester.tap(
        find.byKey(const ValueKey('create-list-confirm-button')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('financial-list-board')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('note-filter-selector')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('new-note-button')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('liquid-bottom-sheet-surface')),
        findsOneWidget,
      );
      expect(find.byIcon(FinancialStyle.currencyIcon('CLP')), findsWidgets);
      await tester.enterText(
        find.byKey(const ValueKey('financial-title')),
        'Compra supermercado',
      );
      await tester.enterText(
        find.byKey(const ValueKey('financial-amount')),
        '15000',
      );
      await tester.enterText(
        find.byKey(const ValueKey('financial-counterparty')),
        'Comercio',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('financial-save')));
      await tester.tap(find.byKey(const ValueKey('financial-save')));
      await tester.pumpAndSettle();
      final list = (await repository.fetchLists()).singleWhere(
        (list) => list.isFinancial,
      );
      var note = (await repository.fetchNotes(list.id)).single;
      expect(note.financialEntry?.amountMinor, 15000);
      await tester.tap(find.byKey(ValueKey('financial-entry-${note.id}')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('financial-status')),
      );
      await tester.tap(find.byKey(const ValueKey('financial-status')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pagado').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('financial-save')));
      await tester.tap(find.byKey(const ValueKey('financial-save')));
      await tester.pumpAndSettle();
      note = (await repository.fetchNotes(list.id)).single;
      expect(note.financialEntry?.status, 'paid');
      expect(
        financialTotals(
          await repository.fetchNotes(list.id),
        )['CLP']!['pending'],
        0,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'a financial template configures a real list without dummy records',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = LocalNotesRepository();
      await tester.pumpWidget(
        NockNockApp(repository: repository, authRepository: _Guest()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('appbar-menu-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-list-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('list-template')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Viaje compartido').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('create-list-confirm-button')),
      );
      await tester.tap(
        find.byKey(const ValueKey('create-list-confirm-button')),
      );
      await tester.pumpAndSettle();
      final created = (await repository.fetchLists()).singleWhere(
        (l) => l.name == 'Viaje compartido',
      );
      expect(created.configuration.type, NoteListType.expenses);
      expect(await repository.fetchNotes(created.id), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'a failed financial save keeps the form and validates who owes money',
    (tester) async {
      final now = DateTime.now();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FinancialEntryEditor(
              list: NoteList(
                id: 'debts',
                name: 'Deudas',
                createdAt: now,
                updatedAt: now,
                configuration: const ListConfiguration(
                  type: NoteListType.receivables,
                ),
              ),
              author: 'Nico',
              onSave: (_) async => throw const NotesPersistenceFailure(),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('financial-title')),
        'Préstamo',
      );
      await tester.enterText(
        find.byKey(const ValueKey('financial-amount')),
        '5000',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('financial-save')));
      await tester.tap(find.byKey(const ValueKey('financial-save')));
      await tester.pumpAndSettle();
      expect(find.text('Indica quién debe este monto'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('financial-counterparty')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('financial-counterparty')),
        'Ana',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('financial-save')));
      await tester.tap(find.byKey(const ValueKey('financial-save')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('financial-entry-editor')),
        findsOneWidget,
      );
      expect(find.text('Préstamo'), findsOneWidget);
      expect(find.text('Ana'), findsOneWidget);
    },
  );
}

class _PagedLocal extends LocalNotesRepository
    implements PaginatedNotesRepository {
  @override
  Future<NotesPage> fetchNotesPage(
    String boardId, {
    String? cursor,
    int limit = 40,
  }) async {
    final all = await fetchNotes(boardId);
    return NotesPage(
      items: all.take(limit).toList(),
      nextCursor: all.length > limit ? 'more' : null,
    );
  }
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
