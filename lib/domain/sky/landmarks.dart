/// "It passes right by Jupiter, then close to Vega": the bright things a
/// pass really goes near, so people can find it by what they can see
/// instead of by compass points.
library;

import 'astro.dart';
import 'catalog.dart';

class Landmark {
  const Landmark(this.name, this.at, this.position, this.distanceDeg);

  /// "Vega", "Jupiter", "the Moon".
  final String name;

  /// When the pass is nearest it.
  final DateTime at;

  /// Where it is in the sky then.
  final Horizontal position;
  final double distanceDeg;
}

/// The bright named stars (brighter than [maxStarMag]), planets and the
/// Moon that [track] passes within [withinDeg] of while at least 10° up,
/// in the order the pass reaches them; at most [max], the nearest kept.
List<Landmark> landmarksAlong({
  required List<({DateTime t, Horizontal h})> track,
  required SkyCatalog catalog,
  required double lat,
  required double lon,
  double withinDeg = 6,
  double maxStarMag = 1.6,
  int max = 2,
}) {
  final up = [for (final p in track) if (p.h.altitudeDeg >= 10) p];
  if (up.isEmpty) return const [];
  final mid = up[up.length ~/ 2].t;
  final candidates = <(String, Horizontal)>[
    for (final s in catalog.stars)
      if (s.name != null && s.mag <= maxStarMag) (s.name!, s.horizontal(mid, lat, lon)),
    for (final p in Planet.values) (p.label, planetHorizontal(p, mid, lat, lon)),
    ('the Moon', moonHorizontal(mid, lat, lon)),
  ];
  final found = <Landmark>[];
  for (final (name, pos) in candidates) {
    if (pos.altitudeDeg < 5) continue;
    Landmark? best;
    for (final p in up) {
      final d = separationDeg(p.h, pos);
      if (d <= withinDeg && (best == null || d < best.distanceDeg)) best = Landmark(name, p.t, pos, d);
    }
    if (best != null) found.add(best);
  }
  found.sort((a, b) => a.distanceDeg.compareTo(b.distanceDeg));
  final kept = found.take(max).toList()..sort((a, b) => a.at.compareTo(b.at));
  return kept;
}

/// "passing right by Jupiter, then close to Vega", or null with none.
String? landmarkWords(List<Landmark> marks) {
  if (marks.isEmpty) return null;
  String one(Landmark m) => '${m.distanceDeg < 2 ? 'right by' : 'close to'} ${m.name}';
  return 'passing ${marks.map(one).join(', then ')}';
}
