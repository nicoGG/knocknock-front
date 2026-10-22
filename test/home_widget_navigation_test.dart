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
