/// "It passes right by Jupiter, then close to Vega": the bright things a
/// pass really goes near, so people can find it by what they can see
/// instead of by compass points.
library;

import 'package:satellite_observer/satellite_observer.dart';

import '../models/sky_event.dart';
import '../orbit/omm.dart';
import 'astro.dart';
import 'catalog.dart';

class Landmark {
  const Landmark(this.name, this.at, this.position, this.distanceDeg, {this.above = true});

  /// "Vega", "Jupiter", "the Moon".
  final String name;

  /// When the pass is nearest it.
  final DateTime at;

  /// Where it is in the sky then.
  final Horizontal position;
  final double distanceDeg;

  /// Whether it's higher in the sky than the pass where they meet.
  final bool above;
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
      if (d <= withinDeg && (best == null || d < best.distanceDeg)) {
        best = Landmark(name, p.t, pos, d, above: pos.altitudeDeg >= p.h.altitudeDeg);
      }
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

/// The landmarks of a pass that carries its orbital elements ('omm'),
/// propagated every 10 s from rise to set; empty when there are none.
List<Landmark> passLandmarks(SkyEvent e, SkyCatalog catalog, double lat, double lon) {
  const passes = {SkyEventType.iss, SkyEventType.tiangong, SkyEventType.starlinkTrain};
  final omm = e.details['omm'];
  if (!passes.contains(e.type) || omm is! Map) return const [];
  try {
    final sat = SatelliteObserver(
      elements: OmmRecord.fromJson(omm.cast<String, Object?>()).toElements(),
      observer: Observer(latitudeDeg: lat, longitudeDeg: lon),
    );
    final track = <({DateTime t, Horizontal h})>[];
    for (var t = e.start; !t.isAfter(e.end); t = t.add(const Duration(seconds: 10))) {
      final look = sat.lookAngleAt(t);
      track.add((t: t, h: Horizontal(look.azimuthDeg, look.elevationDeg)));
    }
    return landmarksAlong(track: track, catalog: catalog, lat: lat, lon: lon);
  } catch (_) {
    return const [];
  }
}

/// Landmark words for a pass, or null when it goes near nothing bright.
String? passLandmarkWords(SkyEvent e, SkyCatalog catalog, double lat, double lon) =>
    landmarkWords(passLandmarks(e, catalog, lat, lon));

/// [e] with its landmarks attached: the words alerts use ('landmarks') and
/// where along the pass each one is ('landmarkPoints'), for drawing.
SkyEvent withLandmarks(SkyEvent e, List<Landmark> marks) {
  final words = landmarkWords(marks);
  if (words == null) return e;
  final total = e.end.difference(e.start).inMilliseconds;
  return e.copyWith(details: {
    ...e.details,
    'landmarks': words,
    'landmarkPoints': [
      for (final m in marks)
        {
          'name': m.name,
          'f': total <= 0 ? 0.5 : (m.at.difference(e.start).inMilliseconds / total).clamp(0.0, 1.0),
          'above': m.above,
          'close': m.distanceDeg < 2,
        },
    ],
  });
}

/// Where along [e] its landmarks are (0 at rise, 1 at set), as attached by
/// [withLandmarks]; empty for anything else.
List<({String name, double f, bool above, bool close})> landmarkPoints(SkyEvent e) {
  final raw = e.details['landmarkPoints'];
  if (raw is! List) return const [];
  return [
    for (final p in raw)
      if (p is Map && p['name'] is String && p['f'] is num)
        (
          name: p['name'] as String,
          f: (p['f'] as num).toDouble().clamp(0.0, 1.0),
          above: p['above'] != false,
          close: p['close'] == true,
        ),
  ];
}

/// Where the landmark called [name] is at [utc]: "the Moon", a planet, or
/// a named star in [catalog]. Null for anything else.
Horizontal? landmarkDirection(String name, SkyCatalog? catalog, DateTime utc, double lat, double lon) {
  if (name == 'the Moon') return moonHorizontal(utc, lat, lon);
  for (final p in Planet.values) {
    if (p.label == name) return planetHorizontal(p, utc, lat, lon);
  }
  return catalog?.stars.where((s) => s.name == name).firstOrNull?.horizontal(utc, lat, lon);
}
