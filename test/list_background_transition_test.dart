import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/presentation/widgets/list_background.dart';

void main() {
  testWidgets('crossfades between list backgrounds without fading content', (
    tester,
  ) async {
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
    expect(find.byKey(const ValueKey('preset-background-lavender')), findsOne);
    expect(find.byKey(const ValueKey('board-content')), findsOne);

    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const ValueKey('preset-background-paper')), findsNothing);
    expect(find.byKey(const ValueKey('preset-background-lavender')), findsOne);
    expect(find.byKey(const ValueKey('board-content')), findsOne);
  });
}
