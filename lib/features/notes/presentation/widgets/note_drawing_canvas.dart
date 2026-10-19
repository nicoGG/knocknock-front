import 'package:nocknock/core/widgets/liquid_alert_dialog.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/presentation/note_palette.dart';
import 'package:nocknock/features/notes/presentation/widgets/liquid_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:nocknock/features/notes/domain/note_drawing.dart';

class DrawingEditorResult {
  const DrawingEditorResult(this.drawing, this.color);
  final NoteDrawing drawing;
  final NoteColor color;
}

Future<DrawingEditorResult?> editNoteDrawing(
  BuildContext context,
  NoteDrawing drawing, {
  required NoteColor noteColor,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  return Navigator.of(context).push<DrawingEditorResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _DrawingEditor(drawing: drawing, noteColor: noteColor),
    ),
  );
}

class NoteDrawingView extends StatelessWidget {
  const NoteDrawingView({
    required this.drawing,
    required this.backgroundColor,
    this.onTap,
    super.key,
  });
  final Color backgroundColor;
  final NoteDrawing drawing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Dibujo de la nota',
    button: onTap != null,
    child: GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: drawing.aspectRatio < 1 ? drawing.aspectRatio : 0.85,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ColoredBox(
            color: backgroundColor,
            child: Center(
              child: AspectRatio(
                aspectRatio: drawing.aspectRatio,
                child: CustomPaint(
                  painter: _DrawingPainter(
                    drawing.strokes,
                    paperStyle: drawing.paperStyle,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _DrawingEditor extends StatefulWidget {
  const _DrawingEditor({required this.drawing, required this.noteColor});
  final NoteColor noteColor;
  final NoteDrawing drawing;
  @override
  State<_DrawingEditor> createState() => _DrawingEditorState();
}

class _DrawingEditorState extends State<_DrawingEditor> {
  static const _aspectRatio = 0.7;
  late final List<DrawingStroke> _strokes = _initialStrokes();
  late NoteColor _background = widget.noteColor;
  late DrawingPaperStyle _paperStyle = widget.drawing.paperStyle;
  final _undo = <List<DrawingStroke>>[];
  final _redo = <List<DrawingStroke>>[];
  DrawingPoint? _lastErase;

  List<DrawingStroke> _initialStrokes() {
    var result = <DrawingStroke>[];
    for (final stroke in widget.drawing.strokes) {
      final points = [
        for (final p in stroke.points)
          DrawingPoint(
            p.x,
            ((p.y - 0.5) * _aspectRatio / widget.drawing.aspectRatio + 0.5)
                .clamp(0, 1),
          ),
      ];
      if (stroke.erase) {
        for (final p in points) {
          result = eraseDrawingAt(result, p, stroke.width / 720, _aspectRatio);
        }
      } else {
        result.add(DrawingStroke(stroke.color, stroke.width, points));
      }
    }
    return result;
  }

  List<DrawingStroke> _snapshot() => [
    for (final s in _strokes) DrawingStroke(s.color, s.width, [...s.points]),
  ];
  void _remember() {
    _undo.add(_snapshot());
    if (_undo.length > 30) _undo.removeAt(0);
    _redo.clear();
  }

  void _erase(DrawingPoint point) {
    final previous = _lastErase ?? point;
    final dx = point.x - previous.x;
    final dy = (point.y - previous.y) / _aspectRatio;
    final radius = _eraserWidth / 720;
    final distance = Offset(dx, dy).distance;
    final steps = (distance / (radius / 2)).ceil().clamp(1, 300);
    var result = _snapshot();
    for (var i = 1; i <= steps; i++) {
      result = eraseDrawingAt(
        result,
        DrawingPoint(
          previous.x + (point.x - previous.x) * i / steps,
          previous.y + (point.y - previous.y) * i / steps,
        ),
        radius,
        _aspectRatio,
      );
    }
    _strokes
      ..clear()
      ..addAll(result);
    _lastErase = point;
  }

  int _color = 0xff292621;
  double _width = 3;
  double _eraserWidth = 24;
  bool _active = false;
  bool _erasing = false;
  bool _panning = false;
  final _canvasTransform = TransformationController();
  final _canvasViewportKey = GlobalKey();

  @override
  void dispose() {
    _canvasTransform.dispose();
    super.dispose();
  }

  void _zoomCanvas(double factor) {
    final current = _canvasTransform.value;
    final scale = current.getMaxScaleOnAxis();
    final next = (scale * factor).clamp(1.0, 4.0);
    final multiplier = next / scale;
    final viewport =
        _canvasViewportKey.currentContext?.findRenderObject() as RenderBox?;
    final center = viewport == null
        ? Offset.zero
        : viewport.size.center(Offset.zero);
    final matrix = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(multiplier, multiplier, 1, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1)
      ..multiply(current);
    setState(() {
      _canvasTransform.value = next == 1 ? Matrix4.identity() : matrix;
    });
  }

  int get _pointCount => _strokes.fold(0, (n, s) => n + s.points.length);

  void _point(Offset position, Size size, {bool start = false}) {
    if (size.isEmpty || (!start && !_active)) return;
    if (!_erasing &&
        (_pointCount >= NoteDrawing.maxPoints ||
            (start && _strokes.length >= NoteDrawing.maxStrokes))) {
      for (var i = 0; i < _strokes.length; i++) {
        final stroke = _strokes[i];
        _strokes[i] = DrawingStroke(
          stroke.color,
          stroke.width,
          simplifyDrawingPoints(stroke.points, 0.001),
        );
      }
      if (_pointCount >= NoteDrawing.maxPoints ||
          (start && _strokes.length >= NoteDrawing.maxStrokes)) {
        if (start) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Límite del dibujo alcanzado. Borra una zona para continuar.',
              ),
            ),
          );
        }
        return;
      }
    }
    final point = DrawingPoint(
      (position.dx / size.width).clamp(0, 1),
      (position.dy / size.height).clamp(0, 1),
    );
    if (_erasing) {
      setState(() {
        if (start) {
          _remember();
          _lastErase = null;
          _active = true;
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
        }
        _erase(point);
      });
      return;
    }
    if (!start && _strokes.last.points.isNotEmpty) {
      final last = _strokes.last.points.last;
      if ((last.x - point.x).abs() + (last.y - point.y).abs() < 0.004) return;
    }
    setState(() {
      if (start) {
        _remember();
        _strokes.add(
          DrawingStroke(
            _color,
            _erasing ? _eraserWidth : _width,
            [],
            erase: _erasing,
          ),
        );
        _redo.clear();
        _active = true;
      }
      _strokes.last.points.add(point);
    });
  }

  Future<void> _pickPaperStyle() async {
    final style = await showLiquidBottomSheet<DrawingPaperStyle>(
      context: context,
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Tipo de hoja',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              for (final style in DrawingPaperStyle.values)
                ListTile(
                  key: ValueKey('drawing-paper-${style.name}'),
                  leading: Icon(switch (style) {
                    DrawingPaperStyle.plain => Icons.crop_square_rounded,
                    DrawingPaperStyle.grid => Icons.grid_on_rounded,
                    DrawingPaperStyle.ruled => Icons.view_headline_rounded,
                  }),
                  title: Text(switch (style) {
                    DrawingPaperStyle.plain => 'Lisa',
                    DrawingPaperStyle.grid => 'Cuadrícula',
                    DrawingPaperStyle.ruled => 'Renglones',
                  }),
                  selected: style == _paperStyle,
                  trailing: style == _paperStyle
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.pop(context, style),
                ),
            ],
          ),
        ),
      ),
    );
    if (mounted && style != null) setState(() => _paperStyle = style);
  }

  Future<void> _pickBackground() async {
    final color = await showLiquidBottomSheet<NoteColor>(
      context: context,
      builder: (context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Color del fondo',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final color in NotePalette.selectableColors)
                    Semantics(
                      label: 'Fondo ${color.name}',
                      selected: _background == color,
                      button: true,
                      child: Material(
                        color: NotePalette.color(color),
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          key: ValueKey('drawing-background-${color.name}'),
                          customBorder: const CircleBorder(),
                          onTap: () => Navigator.pop(context, color),
                          child: SizedBox.square(
                            dimension: 48,
                            child: _background == color
                                ? const Icon(
                                    Icons.check_rounded,
                                    color: Colors.black87,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted && color != null) setState(() => _background = color);
  }

  Future<void> _resetDrawing() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => LiquidAlertDialog(
        title: const Text('¿Reiniciar dibujo?'),
        content: const Text(
          'Se borrarán todos los trazos. El color del fondo se conservará.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('confirm-reset-note-drawing'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reiniciar'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _remember();
      _strokes.clear();
      _active = false;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Dibujar'),
      actions: [
        IconButton(
          key: const ValueKey('drawing-paper-action'),
          tooltip: 'Tipo de hoja',
          icon: Icon(
            _paperStyle == DrawingPaperStyle.ruled
                ? Icons.view_headline_rounded
                : Icons.grid_on_rounded,
          ),
          onPressed: _pickPaperStyle,
        ),
        IconButton(
          key: const ValueKey('reset-note-drawing'),
          tooltip: 'Reiniciar dibujo',
          onPressed: _strokes.isEmpty ? null : _resetDrawing,
          icon: const Icon(Icons.restart_alt_rounded),
        ),
        IconButton(
          key: const ValueKey('drawing-background-action'),
          tooltip: 'Color del fondo',
          icon: const Icon(Icons.format_color_fill_rounded),
          onPressed: _pickBackground,
        ),
        TextButton(
          key: const ValueKey('save-note-drawing'),
          onPressed: () => Navigator.pop(
            context,
            DrawingEditorResult(
              NoteDrawing(
                _strokes,
                aspectRatio: _aspectRatio,
                paperStyle: _paperStyle,
              ),
              _background,
            ),
          ),
          child: const Text('Guardar'),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final color in [
                0xff292621,
                0xffdc3947,
                0xff2476ce,
                0xff27865a,
                0xff8b4cbb,
              ])
                IconButton(
                  tooltip: 'Color de lápiz',
                  isSelected: !_erasing && _color == color,
                  onPressed: () => setState(() {
                    _color = color;
                    _erasing = false;
                  }),
                  icon: Icon(
                    !_erasing && _color == color
                        ? Icons.check_circle
                        : Icons.circle,
                    color: Color(color),
                  ),
                ),
              IconButton(
                key: const ValueKey('note-drawing-eraser'),
                tooltip: 'Goma de borrar',
                isSelected: _erasing,
                onPressed: () => setState(() => _erasing = !_erasing),
                icon: const _EraserIcon(),
              ),
              IconButton(
                tooltip: 'Deshacer trazo',
                onPressed: _undo.isEmpty
                    ? null
                    : () => setState(() {
                        _redo.add(_snapshot());
                        _strokes
                          ..clear()
                          ..addAll(_undo.removeLast());
                        _active = false;
                      }),
                icon: const Icon(Icons.undo),
              ),
              IconButton(
                tooltip: 'Rehacer trazo',
                onPressed: _redo.isEmpty
                    ? null
                    : () => setState(() {
                        _undo.add(_snapshot());
                        _strokes
                          ..clear()
                          ..addAll(_redo.removeLast());
                        _active = false;
                      }),
                icon: const Icon(Icons.redo),
              ),
            ],
          ),
          Slider(
            value: _erasing ? _eraserWidth : _width,
            min: _erasing ? 8 : 1,
            max: _erasing ? 64 : 12,
            divisions: _erasing ? 28 : 11,
            label: _erasing
                ? 'Goma ${_eraserWidth.round()}'
                : 'Lápiz ${_width.round()}',
            onChanged: (value) => setState(() {
              if (_erasing) {
                _eraserWidth = value;
              } else {
                _width = value;
              }
            }),
          ),
          Expanded(
            child: InteractiveViewer(
              key: _canvasViewportKey,
              transformationController: _canvasTransform,
              minScale: 1,
              maxScale: 4,
              panEnabled: _panning,
              scaleEnabled: _panning,
              child: Center(
                child: AspectRatio(
                  aspectRatio: _aspectRatio,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = constraints.biggest;
                      return ClipRect(
                        child: GestureDetector(
                          key: const ValueKey('note-drawing-canvas'),
                          behavior: HitTestBehavior.opaque,
                          onPanDown: _panning
                              ? null
                              : (d) =>
                                    _point(d.localPosition, size, start: true),
                          onPanUpdate: _panning
                              ? null
                              : (d) => _point(d.localPosition, size),
                          onPanEnd: _panning ? null : (_) => _active = false,
                          onPanCancel: _panning ? null : () => _active = false,
                          child: ColoredBox(
                            color: NotePalette.color(_background),
                            child: CustomPaint(
                              size: size,
                              painter: _DrawingPainter(
                                _strokes,
                                paperStyle: _paperStyle,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Alejar lienzo',
                onPressed: () => _zoomCanvas(1 / 1.5),
                icon: const Icon(Icons.zoom_out_rounded),
              ),
              ListenableBuilder(
                listenable: _canvasTransform,
                builder: (context, _) => Text(
                  '${(_canvasTransform.value.getMaxScaleOnAxis() * 100).round()}%',
                ),
              ),
              IconButton(
                key: const ValueKey('zoom-in-note-drawing'),
                tooltip: 'Ampliar lienzo',
                onPressed: () => _zoomCanvas(1.5),
                icon: const Icon(Icons.zoom_in_rounded),
              ),
              IconButton(
                tooltip: 'Mover lienzo',
                isSelected: _panning,
                onPressed: () => setState(() {
                  _panning = !_panning;
                  _active = false;
                }),
                icon: const Icon(Icons.pan_tool_outlined),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              _panning
                  ? 'Arrastra o pellizca para mover y ampliar. Desactiva la mano para dibujar.'
                  : 'Amplía el lienzo y usa la mano para moverte.',
            ),
          ),
        ],
      ),
    ),
  );
}

class _DrawingPainter extends CustomPainter {
  _DrawingPainter(this.strokes, {this.paperStyle = DrawingPaperStyle.plain});
  final DrawingPaperStyle paperStyle;
  final List<DrawingStroke> strokes;
  @override
  void paint(Canvas canvas, Size size) {
    if (paperStyle != DrawingPaperStyle.plain && !size.isEmpty) {
      final guide = Paint()
        ..color = const Color(0xFF292621).withValues(alpha: 0.13)
        ..strokeWidth = size.width / 720;
      final spacing =
          size.width / (paperStyle == DrawingPaperStyle.grid ? 18 : 12);
      for (var y = spacing; y < size.height; y += spacing) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), guide);
      }
      if (paperStyle == DrawingPaperStyle.grid) {
        for (var x = spacing; x < size.width; x += spacing) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), guide);
        }
      } else {
        final margin = Paint()
          ..color = const Color(0xFFC25757).withValues(alpha: 0.25)
          ..strokeWidth = size.width / 600;
        canvas.drawLine(
          Offset(size.width * 0.1, 0),
          Offset(size.width * 0.1, size.height),
          margin,
        );
      }
    }
    canvas.saveLayer(Offset.zero & size, Paint());
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..blendMode = stroke.erase ? BlendMode.clear : BlendMode.srcOver
        ..color = Color(stroke.color)
        ..strokeWidth = stroke.width * size.width / 360
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final first = stroke.points.first;
      if (stroke.points.length == 1) {
        canvas.drawCircle(
          Offset(first.x * size.width, first.y * size.height),
          paint.strokeWidth / 2,
          paint..style = PaintingStyle.fill,
        );
      } else {
        final path = Path()
          ..moveTo(first.x * size.width, first.y * size.height);
        for (final p in stroke.points.skip(1)) {
          path.lineTo(p.x * size.width, p.y * size.height);
        }
        canvas.drawPath(path, paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DrawingPainter oldDelegate) => true;
}

class _EraserIcon extends StatelessWidget {
  const _EraserIcon();

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size.square(24),
    painter: _EraserIconPainter(
      IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface,
    ),
  );
}

class _EraserIconPainter extends CustomPainter {
  const _EraserIconPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final outline = Path()
      ..moveTo(3, 14)
      ..lineTo(13, 4)
      ..quadraticBezierTo(14, 3, 15, 4)
      ..lineTo(21, 10)
      ..quadraticBezierTo(22, 11, 21, 12)
      ..lineTo(12, 21)
      ..lineTo(9, 21)
      ..close();
    canvas.drawPath(outline, paint);
    canvas.drawLine(const Offset(8, 9), const Offset(16, 17), paint);
    canvas.drawLine(const Offset(9, 21), const Offset(22, 21), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EraserIconPainter oldDelegate) =>
      color != oldDelegate.color;
}
