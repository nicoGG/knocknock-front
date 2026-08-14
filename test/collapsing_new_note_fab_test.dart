import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/presentation/widgets/collapsing_new_note_fab.dart';

void main() {
  testWidgets('progressively compacts the new-note button while scrolling', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
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
    expect(tester.getSize(button).height, closeTo(56, 0.1));
    expect(find.byIcon(Icons.add_rounded), findsOne);
    final androidGlass = find.byKey(const ValueKey('new-note-fab-glass-blur'));
    expect(androidGlass, findsOne);
    expect(tester.widget(androidGlass), isNot(isA<BackdropFilter>()));

    final surface = tester.widget<Ink>(
      find.byKey(const ValueKey('new-note-fab-glass-surface')),
    );
    final decoration = surface.decoration! as BoxDecoration;
    final gradient = decoration.gradient! as LinearGradient;
    expect(gradient.colors, everyElement(isNot(equals(Colors.black))));
    expect(gradient.colors.last.a, lessThan(1));

    await tester.tap(button);
    expect(tapCount, 1);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('desktop new-note button keeps the theme tint in its glass', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const themeColor = Color(0xFF7A5AF8);
    var tapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: GlassNewNoteButton(
              key: const ValueKey('new-note-button'),
              onPressed: () => tapCount++,
              backgroundColor: themeColor,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ),
    );

    final desktopGlass = find.byKey(
      const ValueKey('new-note-button-glass-blur'),
    );
    expect(desktopGlass, findsOne);
    expect(tester.widget(desktopGlass), isA<BackdropFilter>());
    final surface = tester.widget<Ink>(
      find.byKey(const ValueKey('new-note-button-glass-surface')),
    );
    final decoration = surface.decoration! as BoxDecoration;
    final gradient = decoration.gradient! as LinearGradient;
    final tint = gradient.colors.last;
    expect(tint.r, themeColor.r);
    expect(tint.g, themeColor.g);
    expect(tint.b, themeColor.b);
    expect(tint.a, lessThan(1));

    await tester.tap(find.byKey(const ValueKey('new-note-button')));
    expect(tapCount, 1);
    debugDefaultTargetPlatformOverride = null;
  });
}
