import 'package:nocknock/features/notes/domain/note.dart';
import 'package:flutter/material.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_drawing_canvas.dart';

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/domain/note_drawing.dart';

void main() {
  testWidgets(
    'selects notebook paper and saves it without changing strokes or color',
    (tester) async {
      DrawingEditorResult? saved;
      final drawing = NoteDrawing(
        [
          DrawingStroke(0xff292621, 3, [
            DrawingPoint(0.2, 0.2),
            DrawingPoint(0.8, 0.8),
          ]),
        ],
        aspectRatio: 0.7,
        paperStyle: DrawingPaperStyle.ruled,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  saved = await editNoteDrawing(
                    context,
                    drawing,
                    noteColor: NoteColor.green,
                  );
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('drawing-paper-action')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ListTile>(find.byKey(const ValueKey('drawing-paper-ruled')))
            .selected,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('drawing-paper-grid')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-note-drawing')));
      await tester.pumpAndSettle();
      final restored = NoteDrawing.decode(saved!.drawing.encode())!;
      expect(restored.paperStyle, DrawingPaperStyle.grid);
      expect(restored.strokes.single.points, hasLength(2));
      expect(restored.strokes.single.points.first.x, 0.2);
      expect(saved!.color, NoteColor.green);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'paper styles survive serialization and older drawings default to plain',
    () {
      for (final style in DrawingPaperStyle.values) {
        expect(
          NoteDrawing.decode(NoteDrawing([], paperStyle: style).encode())!
              .paperStyle,
          style,
        );
      }
      expect(
        NoteDrawing.decode(
          '{"type":"nocknock-drawing","version":1,"strokes":[]}',
        )!.paperStyle,
        DrawingPaperStyle.plain,
      );
    },
  );

  test('erasing clips sparse segments and releases stored geometry', () {
    final original = [
      DrawingStroke(0xff292621, 1, [
        DrawingPoint(0, 0.5),
        DrawingPoint(1, 0.5),
      ]),
    ];
    final clipped = eraseDrawingAt(
      original,
      const DrawingPoint(0.5, 0.5),
      0.1,
      0.7,
    );
    expect(clipped, hasLength(2));
    expect(clipped.first.points.first.x, 0);
    expect(clipped.first.points.last.x, closeTo(0.4, 0.002));
    expect(clipped.last.points.first.x, closeTo(0.6, 0.002));
    expect(clipped.last.points.last.x, 1);
    final cleared = eraseDrawingAt(
      original,
      const DrawingPoint(0.5, 0.5),
      1,
      0.7,
    );
    expect(cleared, isEmpty);
  });

  testWidgets('reset asks for confirmation and preserves the background', (
    tester,
  ) async {
    DrawingEditorResult? saved;
    final drawing = NoteDrawing([
      DrawingStroke(0xff292621, 3, [
        DrawingPoint(0.2, 0.2),
        DrawingPoint(0.8, 0.8),
      ]),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                saved = await editNoteDrawing(
                  context,
                  drawing,
                  noteColor: NoteColor.green,
                );
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reset-note-drawing')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('reset-note-drawing')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const ValueKey('reset-note-drawing')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-reset-note-drawing')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('reset-note-drawing')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('save-note-drawing')));
    await tester.pumpAndSettle();
    expect(saved!.drawing.strokes, isEmpty);
    expect(saved!.color, NoteColor.green);
  });

  testWidgets('can erase a drawing already at the point limit', (tester) async {
    DrawingEditorResult? saved;
    final full = NoteDrawing([
      DrawingStroke(
        0xff292621,
        3,
        List.generate(
          NoteDrawing.maxPoints,
          (i) => DrawingPoint(i / (NoteDrawing.maxPoints - 1), 0.5),
        ),
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                saved = await editNoteDrawing(
                  context,
                  full,
                  noteColor: NoteColor.yellow,
                );
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-drawing-eraser')));
    final canvas = find.byKey(const ValueKey('note-drawing-canvas'));
    expect(
      tester.getSize(canvas).height,
      greaterThan(tester.getSize(canvas).width),
    );
    await tester.dragFrom(tester.getCenter(canvas), const Offset(30, 30));
    await tester.pump();
    expect(find.textContaining('Límite del dibujo alcanzado'), findsNothing);
    await tester.tap(find.byTooltip('Color de lápiz').first);
    await tester.dragFrom(
      tester.getCenter(canvas) + const Offset(0, -30),
      const Offset(20, 0),
    );
    await tester.pump();
    expect(find.textContaining('Límite del dibujo alcanzado'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('save-note-drawing')));
    await tester.pumpAndSettle();
    expect(saved!.drawing.strokes.every((s) => !s.erase), isTrue);
    expect(
      saved!.drawing.strokes.fold<int>(0, (n, s) => n + s.points.length),
      lessThan(NoteDrawing.maxPoints),
    );
    expect(NoteDrawing.decode(saved!.drawing.encode()), isNotNull);
  });

  testWidgets('geometry erasing survives saving and undo redo', (tester) async {
    DrawingEditorResult? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                saved = await editNoteDrawing(
                  context,
                  const NoteDrawing([]),
                  noteColor: NoteColor.yellow,
                );
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    final canvas = find.byKey(const ValueKey('note-drawing-canvas'));
    await tester.dragFrom(tester.getCenter(canvas), const Offset(50, 20));
    await tester.tap(find.byKey(const ValueKey('note-drawing-eraser')));
    await tester.dragFrom(tester.getCenter(canvas), const Offset(20, 50));
    await tester.tap(find.byTooltip('Deshacer trazo'));
    await tester.pump();
    await tester.tap(find.byTooltip('Rehacer trazo'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('drawing-background-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('drawing-background-blue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-note-drawing')));
    await tester.pumpAndSettle();
    expect(saved!.color, NoteColor.blue);
    final reloaded = NoteDrawing.decode(saved!.drawing.encode())!;
    expect(reloaded.strokes.every((s) => !s.erase), isTrue);
    expect(reloaded.aspectRatio, 0.7);
    expect(tester.takeException(), isNull);
  });

  test(
    'drawing payload stays within plaintext and ciphertext transport limits',
    () {
      final drawing = NoteDrawing(
        List.generate(
          100,
          (i) => DrawingStroke(
            0xffffffff,
            12,
            List.generate(9, (j) => const DrawingPoint(0.123, 0.987)),
          ),
        ),
      );
      final encoded = drawing.encode();
      expect(encoded.length, lessThan(30000));
      expect(base64Encode(utf8.encode(encoded)).length + 512, lessThan(50000));
      final decoded = NoteDrawing.decode(encoded)!;
      expect(decoded.strokes.length, 100);
      expect(decoded.strokes.first.points.first.x, 0.123);
    },
  );
  test('malformed, excessive, and non-drawing payloads are ignored', () {
    expect(NoteDrawing.decode('[{"insert":"text"}]'), isNull);
    expect(NoteDrawing.decode('{bad'), isNull);
    expect(
      NoteDrawing.decode(
        NoteDrawing([
          DrawingStroke(1, 3, [DrawingPoint(2, 0)]),
        ]).encode(),
      ),
      isNull,
    );
    expect(
      NoteDrawing.decode(
        NoteDrawing([
          DrawingStroke(
            1,
            3,
            List.filled(NoteDrawing.maxPoints + 1, const DrawingPoint(0, 0)),
          ),
        ]).encode(),
      ),
      isNull,
    );
  });
}
