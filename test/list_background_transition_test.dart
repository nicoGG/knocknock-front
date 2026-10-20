import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/presentation/widgets/list_background.dart';

void main() {
  testWidgets('uses the active color theme while the board is loading', (
    tester,
  ) async {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF168F8A),
      brightness: Brightness.dark,
      surface: const Color(0xFF171714),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: colorScheme),
        home: const ListBoardBackground(
          appearance: ListAppearance(),
          useThemeBackground: true,
          child: SizedBox.expand(),
        ),
      ),
    );

    final background = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('loading-theme-background')),
    );
    final gradient = (background.decoration as BoxDecoration).gradient!;

    expect(gradient.colors, everyElement(isNot(colorScheme.surface)));
    expect(find.byKey(const ValueKey('preset-background-paper')), findsNothing);
  });

  testWidgets(
    'keeps an opaque stable background underneath the entering list',
    (tester) async {
      Widget board(ListAppearance appearance) => MaterialApp(
        home: ListBoardBackground(
          appearance: appearance,
          child: const ColoredBox(
            key: ValueKey('board-content'),
            color: Colors.transparent,
          ),
        ),
      );

      await tester.pumpWidget(board(const ListAppearance()));
      expect(find.byKey(const ValueKey('preset-background-paper')), findsOne);
      final transitionOpacity = find.byKey(
        const ValueKey('background-transition-opacity'),
      );

      await tester.pumpWidget(
        board(
          const ListAppearance(
            backgroundPreset: ListBackgroundPreset.lavender,
            backgroundBlur: 6,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 240));

      expect(find.byKey(const ValueKey('preset-background-paper')), findsOne);
      expect(
        find.byKey(const ValueKey('preset-background-lavender')),
        findsOne,
      );
      expect(find.byKey(const ValueKey('board-content')), findsOne);
      final outgoingOpacity = tester.widget<Opacity>(
        find.ancestor(
          of: find.byKey(const ValueKey('preset-background-paper')),
          matching: transitionOpacity,
        ),
      );
      expect(outgoingOpacity.opacity, 1);
      final enteringOpacity = tester.widget<Opacity>(
        find.ancestor(
          of: find.byKey(const ValueKey('preset-background-lavender')),
          matching: transitionOpacity,
        ),
      );
      expect(enteringOpacity.opacity, inExclusiveRange(0, 1));
      expect(
        find.byKey(const ValueKey('background-transition-blur')),
        findsNothing,
      );
      expect(find.byType(Transform), findsNothing);

      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.byKey(const ValueKey('preset-background-paper')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('preset-background-lavender')),
        findsOne,
      );
      expect(find.byKey(const ValueKey('board-content')), findsOne);
      expect(
        find.byKey(const ValueKey('background-transition-blur')),
        findsNothing,
      );
    },
  );
}
