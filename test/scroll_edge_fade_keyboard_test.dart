import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/presentation/widgets/scroll_edge_fade.dart';

void main() {
  testWidgets('scroll end during keyboard layout defers fade updates', (
    tester,
  ) async {
    final height = ValueNotifier<double>(240);
    addTearDown(height.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<double>(
            valueListenable: height,
            builder: (context, value, _) => SizedBox(
              height: value,
              child: ScrollEdgeFade(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // A drag can end synchronously from applyContentDimensions when the
                    // keyboard changes the viewport and makes the content fit again.
                    ScrollEndNotification(
                      context: context,
                      metrics: FixedScrollMetrics(
                        minScrollExtent: 0,
                        maxScrollExtent: value < 200 ? 200 : 0,
                        pixels: 0,
                        viewportDimension: constraints.maxHeight,
                        axisDirection: AxisDirection.down,
                        devicePixelRatio: 1,
                      ),
                    ).dispatch(context);
                    return const SizedBox.expand();
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final value in [140.0, 240.0, 150.0, 240.0]) {
      height.value = value;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('resizing while dragging a scrollable keeps the fade stable', (
    tester,
  ) async {
    final height = ValueNotifier<double>(200);
    addTearDown(height.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<double>(
            valueListenable: height,
            builder: (context, value, _) => SizedBox(
              height: value,
              child: ScrollEdgeFade(
                child: SingleChildScrollView(
                  child: SizedBox(
                    height: 450,
                    child: Column(
                      children: const [TextField(), Text('Contenido')],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SingleChildScrollView)),
    );
    await gesture.moveBy(const Offset(0, -80));
    await tester.pump();
    height.value = 600;
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
