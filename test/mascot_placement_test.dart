import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/assistant/assistant_mascot.dart';
import 'package:nocknock/features/assistant/mascot_placement.dart';

void main() {
  test('placement clears controls and stays within small viewports', () {
    const viewport = Size(320, 480);
    const size = Size(52, 52);
    const button = Rect.fromLTWH(250, 360, 60, 60);
    final position = mascotPlacement(viewport, size, const Offset(260, 365), [
      button,
    ])!;
    expect((position & size).overlaps(button.inflate(8)), isFalse);
    expect((Offset.zero & viewport).contains(position), isTrue);
    expect(position.dx + size.width, lessThanOrEqualTo(viewport.width));
    expect(position.dy + size.height, lessThanOrEqualTo(viewport.height));
    expect(mascotPlacement(const Size(40, 40), size, Offset.zero, []), isNull);
    expect(
      mascotPlacement(viewport, size, Offset.zero, [Offset.zero & viewport]),
      isNull,
    );
  });

  testWidgets(
    'moving controls displace Nocky; dragging and screen positions remain independent',
    (tester) async {
      final global = ValueNotifier<Alignment?>(Alignment.topRight);
      final placements = <String, Alignment>{};
      var screen = 'Notas';
      var button = const Offset(40, 100);
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: MascotPosition(
            position: global,
            placements: placements,
            dismissedTips: const {},
            onDismiss: (_) {},
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return AssistantSurface(
                  label: screen,
                  onOpen: ([_]) {},
                  child: Scaffold(
                    body: Stack(
                      children: [
                        Positioned(
                          left: button.dx,
                          top: button.dy,
                          child: IconButton(
                            key: const ValueKey('control'),
                            onPressed: () {},
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final mascot = find.byKey(const ValueKey('nock-mascot'));
      final initial = tester.getRect(mascot);
      // Even a legacy global placement must not pin every screen to the top.
      expect(initial.top, greaterThan(200));
      update(() => button = initial.topLeft);
      await tester.pumpAndSettle();
      expect(
        tester
            .getRect(mascot)
            .overlaps(
              tester.getRect(find.byKey(const ValueKey('control'))).inflate(8),
            ),
        isFalse,
      );
      await tester.drag(mascot, const Offset(-200, -150));
      await tester.pumpAndSettle();
      final manual = tester.getRect(mascot);
      expect(placements['Notas'], isNotNull);
      update(() => screen = 'Vista previa');
      await tester.pumpAndSettle();
      expect(tester.getRect(mascot), isNot(manual));
      update(() => screen = 'Notas');
      await tester.pumpAndSettle();
      expect(tester.getRect(mascot), manual);
      // Release on a control: the preferred position remains movable, but the
      // resting mascot yields the actual button's touch area.
      await tester.drag(
        mascot,
        tester.getCenter(find.byKey(const ValueKey('control'))) -
            tester.getCenter(mascot),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getRect(mascot)
            .overlaps(
              tester.getRect(find.byKey(const ValueKey('control'))).inflate(8),
            ),
        isFalse,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      global.dispose();
    },
  );
  testWidgets(
    'outside touches close suggestions without consuming taps or scrolls',
    (tester) async {
      final position = ValueNotifier<Alignment?>(null);
      final scroll = ScrollController();
      var taps = 0;
      final dismissed = <MascotTip>[];
      await tester.pumpWidget(
        MaterialApp(
          home: MascotPosition(
            position: position,
            dismissedTips: const {},
            onDismiss: dismissed.add,
            child: AssistantSurface(
              label: 'Prueba',
              topic: MascotTopic.list,
              onOpen: ([_]) {},
              child: Scaffold(
                body: ListView(
                  controller: scroll,
                  children: [
                    TextButton(
                      onPressed: () => taps++,
                      child: const Text('Otra acción'),
                    ),
                    const SizedBox(height: 1800),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Cerrar sugerencia'), findsOneWidget);
      await tester.tap(find.text('Otra acción'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Cerrar sugerencia'), findsNothing);
      expect(taps, 1);
      expect(dismissed, isEmpty);
      await tester.pump(const Duration(seconds: 19));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Cerrar sugerencia'), findsOneWidget);
      await tester.dragFrom(const Offset(100, 300), const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Cerrar sugerencia'), findsNothing);
      expect(scroll.offset, greaterThan(0));
      expect(dismissed, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      position.dispose();
      scroll.dispose();
    },
  );
  testWidgets(
    'selected filters remain protected while large note cards do not reserve the whole board',
    (tester) async {
      final position = ValueNotifier<Alignment?>(null);
      await tester.pumpWidget(
        MaterialApp(
          home: MascotPosition(
            position: position,
            dismissedTips: const {},
            onDismiss: (_) {},
            child: AssistantSurface(
              label: 'Tablero',
              onOpen: ([_]) {},
              child: Scaffold(
                body: Stack(
                  children: [
                    Positioned.fill(
                      child: InkWell(
                        onTap: () {},
                        child: const SizedBox.expand(),
                      ),
                    ),
                    const Positioned(
                      right: 10,
                      bottom: 70,
                      child: SizedBox(
                        width: 90,
                        height: 52,
                        child: InkWell(
                          key: ValueKey('selected-filter'),
                          child: Text('Todas'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final mascot = tester.getRect(find.byKey(const ValueKey('nock-mascot')));
      final filter = tester.getRect(
        find.byKey(const ValueKey('selected-filter')),
      );
      expect(mascot.overlaps(filter.inflate(8)), isFalse);
      expect(mascot.top, greaterThan(300));
      await tester.pumpWidget(const SizedBox.shrink());
      position.dispose();
    },
  );
}
