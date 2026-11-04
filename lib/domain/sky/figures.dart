/// The artwork of each constellation (`assets/sky/figures.json`, from
/// Stellarium's modern sky culture; see `tool/figures/`). Each image is
/// pinned to the sky by three anchor stars: where they land on screen fixes
/// where the whole picture goes.
library;

import 'dart:math';

class ConstellationFigure {
  const ConstellationFigure({required this.id, required this.file, required this.width, required this.height, required this.anchors});

  final String id; // IAU abbreviation, as Constellation.id
  final String file; // under assets/sky/figures/
  final double width, height; // the image's pixel size the anchors refer to
  final List<({double x, double y, double raDeg, double decDeg})> anchors;

  static List<ConstellationFigure> listFromJson(Map<String, Object?> json) {
    double d(Object? x) => (x as num).toDouble();
    return [
      for (final f in (json['figures'] as List? ?? const []).cast<Map>())
        ConstellationFigure(
          id: f['id'] as String,
          file: f['file'] as String,
          width: d((f['size'] as List)[0]),
          height: d((f['size'] as List)[1]),
          anchors: [
            for (final a in (f['anchors'] as List).cast<List>()) (x: d(a[0]), y: d(a[1]), raDeg: d(a[2]), decDeg: d(a[3])),
          ],
        ),
    ];
  }
}

/// The affine map taking three points [from] onto three points [to], as
/// (a, b, c, d, e, f) with x' = a·x + c·y + e and y' = b·x + d·y + f; null
/// when [from] are in a line.
(double, double, double, double, double, double)? affineFrom3(List<(double, double)> from, List<(double, double)> to) {
  final [(x0, y0), (x1, y1), (x2, y2)] = from;
  final det = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0);
  if (det.abs() < 1e-9) return null;
  final [(u0, v0), (u1, v1), (u2, v2)] = to;
  // Solve for the image's two edge vectors, then the offset.
  final a = ((u1 - u0) * (y2 - y0) - (u2 - u0) * (y1 - y0)) / det;
  final c = ((u2 - u0) * (x1 - x0) - (u1 - u0) * (x2 - x0)) / det;
  final b = ((v1 - v0) * (y2 - y0) - (v2 - v0) * (y1 - y0)) / det;
  final d = ((v2 - v0) * (x1 - x0) - (v1 - v0) * (x2 - x0)) / det;
  return (a, b, c, d, u0 - a * x0 - c * y0, v0 - b * x0 - d * y0);
}

/// How far [p] is from the triangle [tri]: 0 inside it, else the distance to
/// its nearest edge. A picture's three anchors span it, so this says whether
/// a point is on the constellation rather than near the middle of its image.
double distanceToTriangle((double, double) p, List<(double, double)> tri) {
  final (px, py) = p;
  double side((double, double) a, (double, double) b) => (b.$1 - a.$1) * (py - a.$2) - (b.$2 - a.$2) * (px - a.$1);
  final s = [side(tri[0], tri[1]), side(tri[1], tri[2]), side(tri[2], tri[0])];
  if (s.every((v) => v >= 0) || s.every((v) => v <= 0)) return 0;
  double toEdge((double, double) a, (double, double) b) {
    final (ax, ay) = a;
    final (bx, by) = b;
    final len2 = (bx - ax) * (bx - ax) + (by - ay) * (by - ay);
    final t = len2 == 0 ? 0.0 : (((px - ax) * (bx - ax) + (py - ay) * (by - ay)) / len2).clamp(0.0, 1.0);
    final dx = ax + t * (bx - ax) - px, dy = ay + t * (by - ay) - py;
    return sqrt(dx * dx + dy * dy);
  }
  return [toEdge(tri[0], tri[1]), toEdge(tri[1], tri[2]), toEdge(tri[2], tri[0])].reduce(min);
}
