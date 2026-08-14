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
}
