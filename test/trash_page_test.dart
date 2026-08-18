import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/data/local_notes_repository.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/logic/notes_cubit.dart';
import 'package:nocknock/features/notes/presentation/trash_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('uses a contextual animated loader while opening the trash', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final preferences = Completer<SharedPreferences>();
    final repository = LocalNotesRepository(
      preferencesLoader: () => preferences.future,
    );
    final cubit = NotesCubit(repository);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: TrashPage(cubit: cubit),
      ),
    );

    expect(find.byKey(const ValueKey('trash-loading-state')), findsOneWidget);
    expect(find.text('Revisando la papelera…'), findsOneWidget);
    expect(find.byKey(const ValueKey('trash-loading-card-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('trash-loading-card-2')), findsOneWidget);

    final before = tester.widget<Container>(
      find.byKey(const ValueKey('trash-loading-card-0')),
    );
    final beforeGradient =
        (before.decoration! as BoxDecoration).gradient! as LinearGradient;
    await tester.pump(const Duration(milliseconds: 260));
    final after = tester.widget<Container>(
      find.byKey(const ValueKey('trash-loading-card-0')),
    );
    final afterGradient =
        (after.decoration! as BoxDecoration).gradient! as LinearGradient;

    expect(afterGradient.begin, isNot(beforeGradient.begin));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    preferences.complete(await SharedPreferences.getInstance());
    await tester.pump();
    unawaited(cubit.close());
  });

  testWidgets('keeps the trash loader still when animations are disabled', (
    tester,
  ) async {
    final preferences = Completer<SharedPreferences>();
    final repository = LocalNotesRepository(
      preferencesLoader: () => preferences.future,
    );
    final cubit = NotesCubit(repository);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: TrashPage(cubit: cubit),
      ),
    );

    final before = tester.widget<Container>(
      find.byKey(const ValueKey('trash-loading-card-0')),
    );
    final beforeGradient =
        (before.decoration! as BoxDecoration).gradient! as LinearGradient;
    await tester.pump(const Duration(milliseconds: 500));
    final after = tester.widget<Container>(
      find.byKey(const ValueKey('trash-loading-card-0')),
    );
    final afterGradient =
        (after.decoration! as BoxDecoration).gradient! as LinearGradient;

    expect(afterGradient.begin, beforeGradient.begin);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    preferences.complete(await SharedPreferences.getInstance());
    await tester.pump();
    unawaited(cubit.close());
  });

  testWidgets('shows deleted notes and restores them', (tester) async {
    final repository = LocalNotesRepository();
    final note = await repository.createNote(
      'home',
      const NoteDraft(
        title: 'Comprar café',
        content: '',
        color: NoteColor.yellow,
        authorName: 'Invitado',
      ),
    );
    await repository.deleteNote(note.id);
    final cubit = NotesCubit(repository);
    await cubit.load();

    await tester.pumpWidget(MaterialApp(home: TrashPage(cubit: cubit)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Papelera'), findsOneWidget);
    expect(find.text('Comprar café'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('trash-retention-notice')),
      findsOneWidget,
    );
    expect(find.text('Restaurar'), findsOneWidget);

    await tester.tap(find.text('Restaurar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('La papelera está vacía'), findsOneWidget);
    expect(await repository.fetchNotes('home'), hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
    unawaited(cubit.close());
  });

  testWidgets('warns before deleting one note or emptying the trash', (
    tester,
  ) async {
    final repository = LocalNotesRepository();
    final first = await repository.createNote(
      'home',
      const NoteDraft(
        title: 'Borrador antiguo',
        content: 'Contenido que todavía se puede recuperar',
        color: NoteColor.pink,
        authorName: 'Invitado',
      ),
    );
    final second = await repository.createNote(
      'home',
      const NoteDraft(
        title: 'Otra nota',
        content: '',
        color: NoteColor.blue,
        authorName: 'Invitado',
      ),
    );
    await repository.deleteNote(first.id);
    await repository.deleteNote(second.id);
    final cubit = NotesCubit(repository);
    await cubit.load();

    await tester.pumpWidget(MaterialApp(home: TrashPage(cubit: cubit)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text('Contenido que todavía se puede recuperar'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('empty-trash-button')), findsOneWidget);
    expect(find.byKey(ValueKey('restore-note-${first.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('delete-note-${first.id}')), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('delete-note-${first.id}')));
    await tester.pumpAndSettle();
    expect(find.text('¿Eliminar definitivamente?'), findsOneWidget);
    expect(find.textContaining('no se puede deshacer'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(await repository.fetchTrash(), hasLength(2));

    await tester.tap(find.byKey(ValueKey('delete-note-${first.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('confirm-delete-note-${first.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('trash-note-${first.id}')), findsNothing);
    expect(await repository.fetchTrash(), hasLength(1));

    await tester.tap(find.byKey(const ValueKey('empty-trash-button')));
    await tester.pumpAndSettle();
    expect(find.text('¿Vaciar la papelera?'), findsOneWidget);
    expect(find.textContaining('No podrás recuperarla'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirm-empty-trash')));
    await tester.pumpAndSettle();

    expect(find.text('La papelera está vacía'), findsOneWidget);
    expect(await repository.fetchTrash(), isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    unawaited(cubit.close());
  });

  testWidgets('trash cards and warning fit narrow screens with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = LocalNotesRepository();
    final note = await repository.createNote(
      'home',
      const NoteDraft(
        title: 'Una nota eliminada con un título bastante largo',
        content: 'Un resumen que también puede ocupar más de una línea.',
        color: NoteColor.orange,
        authorName: 'Invitado',
      ),
    );
    await repository.deleteNote(note.id);
    final cubit = NotesCubit(repository);
    await cubit.load();

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: TrashPage(cubit: cubit),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byKey(const ValueKey('trash-list')),
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('delete-note-${note.id}')));
    await tester.pumpAndSettle();
    expect(find.text('¿Eliminar definitivamente?'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    unawaited(cubit.close());
  });
}
