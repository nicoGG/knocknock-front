import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/core/theme/app_theme.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/presentation/note_hero.dart';
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

  testWidgets('a note exposes a shared transition into its detail', (
    tester,
  ) async {
    await tester.pumpWidget(_cardHarness(note: _note()));

    final hero = tester.widget<Hero>(find.byType(Hero));
    expect(hero.tag, noteHeroTag('note-1', variant: 'grid'));
    expect(hero.transitionOnUserGestures, isTrue);
    expect(tester.widget<HeroMode>(find.byType(HeroMode)).enabled, isTrue);
  });

  testWidgets('the large preview card reacts without opening the note', (
    tester,
  ) async {
    var note = _note();
    var openCalls = 0;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                height: 560,
                child: PostItCard(
                  note: note,
                  layout: PostItCardLayout.large,
                  currentUserId: 'owner-1',
                  reactionAuthorNames: const {'owner-1': 'Tú'},
                  onToggleReaction: (emoji) async {
                    setState(
                      () => note = note.copyWith(
                        reactions: [
                          NoteReaction(
                            emoji: emoji,
                            userUids: const ['owner-1'],
                          ),
                        ],
                      ),
                    );
                  },
                  onToggle: () {},
                  onPin: () {},
                  onOpen: () => openCalls += 1,
                  onChecklistToggle: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('add-note-reaction-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reaction-option-🔥')), findsOneWidget);
    expect(find.byKey(const ValueKey('reaction-option-🚀')), findsOneWidget);
    expect(find.byKey(const ValueKey('reaction-option-😡')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reaction-option-🔥')));
    await tester.pumpAndSettle();

    final reaction = find.byKey(const ValueKey('note-reaction-note-1-🔥'));
    expect(reaction, findsOneWidget);
    expect(openCalls, 0);

    await tester.longPress(reaction);
    await tester.pumpAndSettle();
    expect(find.text('🔥  Tú'), findsOneWidget);
    expect(openCalls, 0);
  });

  testWidgets('grid reactions float above the note without overflowing', (
    tester,
  ) async {
    var openCalls = 0;
    final note = _note().copyWith(
      reactions: const [
        NoteReaction(emoji: '❤️', userUids: ['user-1']),
        NoteReaction(emoji: '😮', userUids: ['user-2']),
        NoteReaction(emoji: '😢', userUids: ['user-3']),
        NoteReaction(emoji: '🎉', userUids: ['user-4']),
        NoteReaction(emoji: '🔥', userUids: ['user-5']),
      ],
    );

    await tester.pumpWidget(
      _cardHarness(
        note: note,
        width: 190,
        height: 270,
        onOpen: () => openCalls += 1,
      ),
    );

    final summary = find.byKey(const ValueKey('note-reactions-summary-note-1'));
    final surface = find.byKey(const ValueKey('note-surface-note-1'));
    final pin = find.byKey(const ValueKey('pin-note-note-1'));
    final summaryRect = tester.getRect(summary);
    final surfaceRect = tester.getRect(surface);
    final firstFloatingReaction = find.byKey(
      const ValueKey('floating-reaction-content-❤️'),
    );
    final animatedEmoji = find.byKey(
      const ValueKey('animated-emoji-transform-floating-note-1-❤️'),
    );
    final initialReactionTop = tester.getTopLeft(firstFloatingReaction).dy;
    final initialEmojiTransform = List<double>.of(
      tester.widget<Transform>(animatedEmoji).transform.storage,
    );

    expect(find.text('+3'), findsOneWidget);
    expect(
      find.descendant(
        of: summary,
        matching: find.byWidgetPredicate(
          (widget) => widget is TweenAnimationBuilder<double>,
        ),
      ),
      findsNWidgets(5),
    );
    expect(summaryRect.top, lessThan(surfaceRect.top));
    expect(summaryRect.bottom, lessThanOrEqualTo(surfaceRect.top + 14));
    expect(summaryRect.right, lessThan(tester.getRect(pin).left));
    expect(find.descendant(of: surface, matching: summary), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(milliseconds: 140));
    final movingReactionTop = tester.getTopLeft(firstFloatingReaction).dy;
    final movingEmojiTransform = List<double>.of(
      tester.widget<Transform>(animatedEmoji).transform.storage,
    );
    expect((movingReactionTop - initialReactionTop).abs(), greaterThan(0.1));
    expect(movingEmojiTransform, isNot(equals(initialEmojiTransform)));
    await tester.pump(const Duration(milliseconds: 700));

    await tester.tapAt(summaryRect.center);
    await tester.pump();
    expect(openCalls, 1);
  });

  testWidgets('grid reaction badges animate in and out', (tester) async {
    var note = _note();
    late StateSetter updateCard;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          updateCard = setState;
          return _cardHarness(note: note, width: 190, height: 270);
        },
      ),
    );
    final summary = find.byKey(const ValueKey('note-reactions-summary-note-1'));
    expect(summary, findsNothing);

    updateCard(
      () => note = note.copyWith(
        reactions: const [
          NoteReaction(emoji: '🔥', userUids: ['user-1']),
        ],
      ),
    );
    await tester.pump();
    expect(summary, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));

    updateCard(() => note = note.copyWith(reactions: const []));
    await tester.pump();
    expect(summary, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    expect(summary, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('floating reactions honor reduced motion', (tester) async {
    final note = _note().copyWith(
      reactions: const [
        NoteReaction(emoji: '🔥', userUids: ['user-1']),
      ],
    );
    await tester.pumpWidget(
      _cardHarness(
        note: note,
        width: 190,
        height: 270,
        disableAnimations: true,
      ),
    );

    final summary = find.byKey(const ValueKey('note-reactions-summary-note-1'));
    expect(summary, findsOneWidget);
    expect(
      find.descendant(
        of: summary,
        matching: find.byWidgetPredicate(
          (widget) => widget is TweenAnimationBuilder<double>,
        ),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('animated-emoji-transform-floating-note-1-🔥')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('app pages enter softly and honor reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(_routeHarness());
    await tester.tap(find.text('Abrir'));
    await tester.pump(const Duration(milliseconds: 80));

    expect(
      find.byKey(const ValueKey('app-page-transition'), skipOffstage: false),
      findsOneWidget,
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(_routeHarness(disableAnimations: true));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('app-page-transition'), skipOffstage: false),
      findsNothing,
    );
    expect(find.text('Destino'), findsOneWidget);
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
    final loadingNoteHeights = List.generate(
      4,
      (index) =>
          tester.getSize(find.byKey(ValueKey('loading-note-$index'))).height,
    );
    expect(loadingNoteHeights.toSet(), hasLength(4));

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

Widget _cardHarness({
  required Note note,
  VoidCallback? onPin,
  VoidCallback? onOpen,
  double width = 300,
  double height = 270,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(disableAnimations: disableAnimations),
      child: child!,
    ),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          height: height,
          child: PostItCard(
            note: note,
            onToggle: () {},
            onPin: onPin ?? () {},
            onOpen: onOpen ?? () {},
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

Widget _routeHarness({bool disableAnimations = false}) {
  return MaterialApp(
    key: ValueKey(disableAnimations),
    theme: AppTheme.light.copyWith(platform: TargetPlatform.android),
    builder: (context, child) => MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Destino')),
              ),
            ),
            child: const Text('Abrir'),
          ),
        ),
      ),
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
