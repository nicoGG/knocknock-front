import 'dart:math' as math;
import 'dart:convert';

enum DrawingPaperStyle { plain, grid, ruled }

/// A versioned vector drawing stored in the encrypted contentDelta payload.
class NoteDrawing {
  const NoteDrawing(
    this.strokes, {
    this.aspectRatio = 1,
    this.paperStyle = DrawingPaperStyle.plain,
  });
  final DrawingPaperStyle paperStyle;
  final double aspectRatio;
  final List<DrawingStroke> strokes;
  static const maxPoints = 3000;
  static const maxStrokes = 1000;

  static NoteDrawing? decode(String? value) {
    if (value == null || value.length > 120000 || !value.startsWith('{')) {
      return null;
    }
    try {
      final json = jsonDecode(value) as Map<String, dynamic>;
      if (json['type'] != 'nocknock-drawing' || json['version'] != 1) {
        return null;
      }
      if ((json['strokes'] as List).length > maxStrokes) return null;
      final strokes = (json['strokes'] as List).map((raw) {
        final stroke = raw as Map<String, dynamic>;
        final points = (stroke['points'] as List).map((raw) {
          final point = raw as List;
          if (point.length != 2) throw const FormatException();
          final x = (point[0] as num).toDouble();
          final y = (point[1] as num).toDouble();
          if (!x.isFinite || !y.isFinite || x < 0 || x > 1 || y < 0 || y > 1) {
            throw const FormatException('Invalid drawing point');
          }
          return DrawingPoint(x, y);
        }).toList();
        final width = (stroke['width'] as num).toDouble();
        final color = stroke['color'] as int;
        if (!width.isFinite ||
            width < 1 ||
            width > (stroke['erase'] == true ? 64 : 16) ||
            color < 0 ||
            color > 0xffffffff) {
          throw const FormatException('Invalid drawing brush');
        }
        if (stroke['erase'] != null && stroke['erase'] is! bool) {
          throw const FormatException();
        }
        return DrawingStroke(
          color,
          width,
          points,
          erase: stroke['erase'] == true,
        );
      }).toList();
      if (strokes.fold<int>(0, (count, s) => count + s.points.length) >
          maxPoints) {
        return null;
      }
      final ratio = (json['aspectRatio'] as num?)?.toDouble() ?? 1;
      if (!ratio.isFinite || ratio < 0.5 || ratio > 1.5) return null;
      final styleName = json['paperStyle'] ?? 'plain';
      final style = DrawingPaperStyle.values
          .where((s) => s.name == styleName)
          .firstOrNull;
      if (style == null) return null;
      return NoteDrawing(strokes, aspectRatio: ratio, paperStyle: style);
    } catch (_) {
      return null;
    }
  }

  String encode() => jsonEncode({
    'type': 'nocknock-drawing',
    'version': 1,
    'aspectRatio': aspectRatio,
    'paperStyle': paperStyle.name,
    'strokes': [
      for (final s in strokes)
        {
          'color': s.color,
          if (s.erase) 'erase': true,
          'width': s.width,
          'points': [
            for (final p in s.points)
              [
                double.parse(p.x.toStringAsFixed(3)),
                double.parse(p.y.toStringAsFixed(3)),
              ],
          ],
        },
    ],
  });
}

class DrawingStroke {
  const DrawingStroke(
    this.color,
    this.width,
    this.points, {
    this.erase = false,
  });
  final bool erase;
  final int color;
  final double width;
  final List<DrawingPoint> points;
}

class DrawingPoint {
  const DrawingPoint(this.x, this.y);
  final double x;
  final double y;
}

/// Removes redundant points while preserving stroke ends and visible corners.
List<DrawingPoint> simplifyDrawingPoints(
  List<DrawingPoint> points,
  double tolerance,
) {
  if (points.length < 3) return [...points];
  final first = points.first;
  final last = points.last;
  final dx = last.x - first.x;
  final dy = last.y - first.y;
  final lengthSquared = dx * dx + dy * dy;
  var maximum = 0.0;
  var index = 0;
  for (var i = 1; i < points.length - 1; i++) {
    final point = points[i];
    final t = lengthSquared == 0
        ? 0.0
        : (((point.x - first.x) * dx + (point.y - first.y) * dy) /
                  lengthSquared)
              .clamp(0.0, 1.0);
    final x = point.x - first.x - t * dx;
    final y = point.y - first.y - t * dy;
    final distance = x * x + y * y;
    if (distance > maximum) {
      maximum = distance;
      index = i;
    }
  }
  if (maximum <= tolerance * tolerance) return [first, last];
  final left = simplifyDrawingPoints(points.sublist(0, index + 1), tolerance);
  final right = simplifyDrawingPoints(points.sublist(index), tolerance);
  return [...left.take(left.length - 1), ...right];
}

/// Erases vector geometry instead of retaining eraser strokes in the payload.
List<DrawingStroke> eraseDrawingAt(
  List<DrawingStroke> strokes,
  DrawingPoint center,
  double radius,
  double aspectRatio,
) {
  final result = <DrawingStroke>[];
  for (final stroke in strokes) {
    if (stroke.erase || stroke.points.isEmpty) continue;
    final r = radius + stroke.width / 720;
    double distance(DrawingPoint p) {
      final dx = p.x - center.x;
      final dy = (p.y - center.y) / aspectRatio;
      return dx * dx + dy * dy;
    }

    if (stroke.points.length == 1) {
      if (distance(stroke.points.first) > r * r) result.add(stroke);
      continue;
    }
    var run = <DrawingPoint>[];
    void flush() {
      if (run.isNotEmpty) {
        result.add(
          DrawingStroke(
            stroke.color,
            stroke.width,
            simplifyDrawingPoints(run, 0.0005),
          ),
        );
      }
      run = [];
    }

    for (var i = 1; i < stroke.points.length; i++) {
      final a = stroke.points[i - 1];
      final b = stroke.points[i];
      final dx = b.x - a.x;
      final dy = (b.y - a.y) / aspectRatio;
      final ox = a.x - center.x;
      final oy = (a.y - center.y) / aspectRatio;
      final aa = dx * dx + dy * dy;
      final bb = 2 * (ox * dx + oy * dy);
      final cc = ox * ox + oy * oy - r * r;
      final cuts = <double>[0, 1];
      final discriminant = bb * bb - 4 * aa * cc;
      if (aa > 0 && discriminant > 0) {
        final root = math.sqrt(discriminant);
        for (final t in [(-bb - root) / (2 * aa), (-bb + root) / (2 * aa)]) {
          if (t > 0 && t < 1) cuts.add(t);
        }
      }
      cuts.sort();
      DrawingPoint at(double t) =>
          DrawingPoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);
      for (var j = 1; j < cuts.length; j++) {
        final from = cuts[j - 1];
        final to = cuts[j];
        if (distance(at((from + to) / 2)) >= r * r) {
          if (run.isEmpty) run.add(at(from));
          run.add(at(to));
        } else {
          flush();
        }
      }
    }
    flush();
  }
  return result;
}
