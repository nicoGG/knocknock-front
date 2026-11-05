import 'package:flutter/painting.dart';

/// Finds the nearest free slot, leaving room for Nocky's animated silhouette.
/// Returns null when the viewport has no room without covering a control.
Offset? mascotPlacement(
  Size viewport,
  Size mascot,
  Offset preferred,
  List<Rect> controls,
) {
  final maxX = viewport.width - mascot.width;
  final maxY = viewport.height - mascot.height;
  if (maxX < 0 || maxY < 0) return null;
  final obstacles = controls.map((rect) => rect.inflate(8)).toList();
  final origin = Offset(
    preferred.dx.clamp(0, maxX),
    preferred.dy.clamp(0, maxY),
  );
  bool free(Offset point) =>
      !obstacles.any((rect) => rect.overlaps(point & mascot));
  if (free(origin)) return origin;
  final xs = <double>{0, maxX, origin.dx};
  final ys = <double>{0, maxY, origin.dy};
  for (final rect in obstacles) {
    xs.addAll(
      [rect.left - mascot.width, rect.right].where((x) => x >= 0 && x <= maxX),
    );
    ys.addAll(
      [rect.top - mascot.height, rect.bottom].where((y) => y >= 0 && y <= maxY),
    );
  }
  Offset? best;
  var distance = double.infinity;
  for (final x in xs) {
    for (final y in ys) {
      final candidate = Offset(x, y);
      final delta = (candidate - origin).distanceSquared;
      if (delta < distance && free(candidate)) {
        best = candidate;
        distance = delta;
      }
    }
  }
  return best;
}
