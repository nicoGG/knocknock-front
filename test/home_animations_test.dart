import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/presentation/widgets/board_loading_state.dart';
import 'package:nocknock/features/notes/presentation/widgets/post_it_card.dart';

void main() {
  testWidgets('a home note lifts on hover and compresses while pressed', (
    tester,
  ) async {
    await tester.pumpWidget(_cardHarness(note: _note()));

    final surface = find.byKey(const ValueKey('note-surface-note-1'));
    final cardScale = find.descendant(
      of: find.byType(PostItCard),
      matching: find.byType(AnimatedScale),
    );
    expect(tester.widget<AnimatedScale>(cardScale).scale, 1);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(surface));
    await tester.pump();
    expect(tester.widget<AnimatedScale>(cardScale).scale, 1.015);

    final touch = await tester.startGesture(tester.getCenter(surface));
    await tester.pump();
    expect(tester.widget<AnimatedScale>(cardScale).scale, 0.985);

    await touch.up();
    await mouse.removePointer();
  });

  testWidgets('the pin morphs when a home note is pinned', (tester) async {
    var note = _note();
    var pinCalls = 0;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => _cardHarness(
          note: note,
          onPin: () {
            pinCalls += 1;
            setState(() => note = note.copyWith(isPinned: true));
          },
        ),
      ),
    );

    expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pin-note-note-1')));
    await tester.pumpAndSettle();

    expect(pinCalls, 1);
    expect(find.byIcon(Icons.push_pin_rounded), findsOneWidget);
    expect(find.byIcon(Icons.push_pin_outlined), findsNothing);
  });

  testWidgets('the home loader mirrors the compact post-it grid', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_loadingHarness(textScale: 2));

    expect(find.byKey(const ValueKey('board-loading-state')), findsOneWidget);
    expect(find.text('Preparando tus notas…'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('loading-note-'),
      ),
      findsNWidgets(4),
    );

    final firstDecoration = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('loading-note-0')),
    );
    final firstGradient =
        (firstDecoration.decoration as BoxDecoration).gradient!
            as LinearGradient;
    await tester.pump(const Duration(milliseconds: 260));
    final nextDecoration = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('loading-note-0')),
    );
    final nextGradient =
        (nextDecoration.decoration as BoxDecoration).gradient!
            as LinearGradient;

    expect(nextGradient.begin, isNot(firstGradient.begin));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the home loader stays still when animations are disabled', (
    tester,
  ) async {
    await tester.pumpWidget(_loadingHarness(disableAnimations: true));

    final before = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('loading-note-0')),
    );
    final beforeGradient =
        (before.decoration as BoxDecoration).gradient! as LinearGradient;
    await tester.pump(const Duration(milliseconds: 500));
    final after = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('loading-note-0')),
    );
    final afterGradient =
        (after.decoration as BoxDecoration).gradient! as LinearGradient;

    expect(afterGradient.begin, beforeGradient.begin);
  });
}

Widget _cardHarness({required Note note, VoidCallback? onPin}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 300,
          height: 270,
          child: PostItCard(
            note: note,
            onToggle: () {},
            onPin: onPin ?? () {},
            onOpen: () {},
            onChecklistToggle: (_) {},
          ),
        ),
      ),
    ),
  );
}

Widget _loadingHarness({bool disableAnimations = false, double textScale = 1}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        disableAnimations: disableAnimations,
        textScaler: TextScaler.linear(textScale),
      ),
      child: const Scaffold(body: BoardLoadingState()),
    ),
  );
}

Note _note() {
  final now = DateTime(2026, 8, 4, 12);
  return Note(
    id: 'note-1',
    boardId: 'board-1',
    title: 'Preparar presentación',
    content: 'Ordenar las ideas importantes para mañana.',
    color: NoteColor.yellow,
    authorName: 'Nico',
    isCompleted: false,
    positionX: 0,
    positionY: 0,
    createdAt: now,
    updatedAt: now,
  );
}
