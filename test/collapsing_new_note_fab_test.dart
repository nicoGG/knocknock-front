import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/presentation/widgets/collapsing_new_note_fab.dart';

void main() {
  testWidgets('progressively compacts the new-note button while scrolling', (
    tester,
  ) async {
    final progress = ValueNotifier<double>(0);
    var tapCount = 0;
    addTearDown(progress.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          floatingActionButton: CollapsingNewNoteFab(
            key: const ValueKey('new-note-fab'),
            scrollProgress: progress,
            onPressed: () => tapCount++,
          ),
        ),
      ),
    );

    final button = find.byKey(const ValueKey('new-note-fab'));
    final expandedWidth = tester.getSize(button).width;

    progress.value = 0.5;
    await tester.pump();
    final middleWidth = tester.getSize(button).width;

    progress.value = 1;
    await tester.pump();
    final compactWidth = tester.getSize(button).width;

    expect(middleWidth, lessThan(expandedWidth));
    expect(middleWidth, greaterThan(compactWidth));
    expect(compactWidth, closeTo(56, 0.1));
    expect(find.byIcon(Icons.add_rounded), findsOne);

    await tester.tap(button);
    expect(tapCount, 1);
  });
}
