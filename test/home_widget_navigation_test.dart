import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nocknock/features/notes/presentation/board_page.dart';
import 'package:nocknock/features/notes/logic/notes_cubit.dart';
import 'package:nocknock/features/finance/financial_entry.dart';
import 'package:nocknock/features/finance/list_configuration.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nocknock/app/nocknock_app.dart';
import 'package:nocknock/features/auth/data/auth_repository.dart';
import 'package:nocknock/features/auth/domain/app_user.dart';
import 'package:nocknock/features/notes/data/local_notes_repository.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('es'));
  const channel = MethodChannel('cl.nocknock/home_widgets');
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  testWidgets(
    'cold widget capture opens the compact editor in its destination list',
    (tester) async {
      final repository = LocalNotesRepository();
      final destination = await repository.createList('Capturas widget');
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('home_widget.guest.list', destination.id);
      Map<String, dynamic>? published;
      Map<String, String>? action = {
        'action': 'capture',
        'owner': 'guest',
        'boardId': destination.id,
      };
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'takeAction') {
          final result = action;
          action = null;
          return result;
        }
        if (call.method == 'readQueue') return '[]';
        if (call.method == 'publish') {
          published =
              jsonDecode(call.arguments as String) as Map<String, dynamic>;
        }
        return null;
      });
      await tester.pumpWidget(
        NockNockApp(repository: repository, authRepository: _Guest()),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quick-capture-sheet')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('quick-capture-text')),
        'Idea desde el widget',
      );
      await tester.tap(find.byKey(const ValueKey('quick-capture-save')));
      await tester.pumpAndSettle();
      expect(
        (await repository.fetchNotes(destination.id)).single.title,
        'Idea desde el widget',
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(published?['total'], 1);
      expect(
        (published?['rows'] as List).single['title'],
        'Idea desde el widget',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('cold widget note opens its preview in the correct list', (
    tester,
  ) async {
    final repository = LocalNotesRepository();
    final destination = await repository.createList('Lista widget');
    final note = await repository.createNote(
      destination.id,
      const NoteDraft(
        title: 'Abrir desde widget',
        content: '',
        color: NoteColor.none,
        authorName: 'Invitado',
      ),
    );
    Map<String, String>? action = {
      'action': 'note',
      'owner': 'guest',
      'boardId': destination.id,
      'noteId': note.id,
    };
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'takeAction') {
        final result = action;
        action = null;
        return result;
      }
      if (call.method == 'readQueue') return '[]';
      return null;
    });
    await tester.pumpWidget(
      NockNockApp(repository: repository, authRepository: _Guest()),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('note-preview-dialog')), findsOneWidget);
    expect(find.text('Abrir desde widget'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  for (final kind in ['note', 'capture']) {
    testWidgets(
      'warm widget $kind returns from nested settings without waiting for a user touch',
      (tester) async {
        final repository = LocalNotesRepository();
        final destination = await repository.createTypedList(
          'Cobros widget',
          const ListConfiguration(
            type: NoteListType.receivables,
            currency: 'USD',
          ),
        );
        final note = await repository.createNote(
          destination.id,
          NoteDraft(
            title: 'Deuda widget',
            content: '',
            color: NoteColor.green,
            authorName: 'Invitado',
            financialData: FinancialEntry(
              amountMinor: 1050,
              currency: 'USD',
              counterparty: 'QA',
              date: DateTime(2026, 10, 22),
            ).encoded,
          ),
        );
        Map<String, String>? action;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            if (call.method == 'takeAction') {
              final next = action;
              action = null;
              return next;
            }
            if (call.method == 'readQueue') return '[]';
            return null;
          },
        );
        await tester.pumpWidget(
          NockNockApp(repository: repository, authRepository: _Guest()),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('appbar-menu-button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('settings-menu-button')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('settings-appearance-button')),
        );
        // The profile background animates continuously; allow its transition
        // to finish without waiting for that ambient animation to settle.
        await tester.pump(const Duration(seconds: 1));
        action = {
          'action': kind,
          'owner': 'guest',
          'boardId': destination.id,
          'noteId': note.id,
        };
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('actionAvailable'),
          ),
          null,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('financial-entry-editor')),
          findsOneWidget,
        );
        if (kind == 'note') {
          expect(find.text('Deuda widget'), findsWidgets);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets(
    'widget completion refreshes the visible guest board without a socket echo',
    (tester) async {
      final repository = LocalNotesRepository();
      final list = await repository.createList('Pendientes widget');
      final note = await repository.createNote(
        list.id,
        const NoteDraft(
          title: 'Tarea widget',
          content: '',
          color: NoteColor.none,
          authorName: 'Invitado',
        ),
      );
      var queue = <Map<String, dynamic>>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'readQueue') return jsonEncode(queue);
        if (call.method == 'acknowledge') {
          queue = [];
          return null;
        }
        return null;
      });
      await tester.pumpWidget(
        NockNockApp(repository: repository, authRepository: _Guest()),
      );
      await tester.pumpAndSettle();
      final cubit = tester.element(find.byType(BoardPage)).read<NotesCubit>();
      await cubit.selectList(list.id);
      await tester.pumpAndSettle();
      expect(cubit.state.notes.single.isCompleted, false);
      queue = [
        {
          'id': note.id,
          'boardId': list.id,
          'owner': 'guest',
          'revision': note.revision,
          'completedAt': DateTime(2026, 10, 22).millisecondsSinceEpoch,
          'mutationId': 'qa-widget-mutation',
        },
      ];
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('queueChanged'),
        ),
        null,
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect((await repository.fetchNotes(list.id)).single.isCompleted, true);
      expect(cubit.state.notes.single.isCompleted, true);
      expect(queue, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
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
