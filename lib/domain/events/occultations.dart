/// The Moon passing in front of a bright star or a planet (an occultation):
/// the star winks out at the Moon's edge, a planet slides behind it.
///
/// LookUp only says "the Moon covers it" when the predicted track passes
/// well inside the Moon's edge, by more than the error in the maths
/// (docs/moon-accuracy.md). Closer than that it could be a graze or a miss,
/// so it says "near the Moon" instead.
library;

import 'dart:math' as math;

import '../sky/astro.dart';
import '../sky/catalog.dart';
import '../sky/sun.dart';

/// Stars this bright or brighter (Aldebaran, Spica, Antares, Pollux,
/// Regulus, Elnath, Alhena). Change it here.
const occultationMaxStarMag = 2.0;

/// How far inside the Moon's edge a star must pass to be called covered.
/// The Moon is good to 12″ and a catalogue star to a few: 1′ is ~4× that.
const occultationStarMarginDeg = 1 / 60;

/// The same for a planet, on top of its own disk (Saturn's rings
/// included). Against the Moon, Schlyter's planets were up to 1.8′ out over
/// 2026–2030 (Saturn; Horizons every 49 h): 3′ is ~1.5× that.
const occultationPlanetMarginDeg = 3 / 60;

/// Measured error of the body's place relative to the Moon, for the ± on
/// the times.
const _starErrorDeg = 16 / 3600, _planetErrorDeg = 121 / 3600;

/// Moon's radius over the Earth's equatorial radius (IAU, as IOTA uses).
const _k = 0.2725076;

/// Seen means the Sun ≤ 6° below the horizon and the Moon ≥ 10° up, as
/// for pairings.
const _maxSunAltDeg = -6.0, _minMoonAltDeg = 10.0;

class Occultation {
  const Occultation({
    required this.body,
    required this.isPlanet,
    required this.covered,
    required this.closest,
    required this.closestSepDeg,
    required this.moonRadiusDeg,
    required this.plusMinus,
    this.disappears,
    this.reappears,
  });

  /// "Regulus", "Saturn".
  final String body;
  final bool isPlanet;

  /// True: the Moon covers it. False: it passes near the Moon's edge.
  final bool covered;

  /// When it's closest to the Moon's centre, and how close (degrees).
  final DateTime closest;
  final double closestSepDeg;
  final double moonRadiusDeg;

  /// When it goes behind the Moon and comes out again (a planet's centre
  /// crossing the edge), each only if it can be seen then. Null unless
  /// [covered].
  final DateTime? disappears, reappears;

  /// How far either time could be out.
  final Duration plusMinus;
}

class _Target {
  _Target(this.name, this.geocentric, {this.planet});
  final String name;
  final Planet? planet;

  /// Apparent place from the Earth's centre.
  final Equatorial Function(DateTime utc) geocentric;

  Equatorial fromTheGround(DateTime utc, double lat, double lon) =>
      planet == null ? geocentric(utc) : planetTopocentric(planet!, utc, lat, lon);
}

/// Occultations of bright [stars] and the planets visible from a site in
/// the next [days], soonest first. [stars] is the catalogue; only those at
/// least [occultationMaxStarMag] bright are tried.
List<Occultation> occultations({
  required DateTime now,
  required double latDeg,
  required double lonDeg,
  required Iterable<Star> stars,
  int days = 14,
}) {
  final targets = <_Target>[
    for (final s in stars)
      if (s.mag <= occultationMaxStarMag && s.name != null)
        _Target(s.name!, (t) => withAberration(catalogEquatorial(s.raDeg, s.decDeg, t, pm: s.pm), t)),
    for (final p in Planet.values) _Target(p.label, (t) => planetEquatorial(p, t), planet: p),
  ];
  final out = <Occultation>[];
  final start = now.toUtc();
  final hours = days * 24;
  final moon = [for (var h = 0; h <= hours; h++) moonEquatorial(start.add(Duration(hours: h)))];
  for (final target in targets) {
    // From the Earth's centre, hourly. Parallax moves the Moon up to 1°
    // and it moves ~0.55° an hour, so anything within 1.8° is a candidate.
    double geoSep(int h) => equatorialSeparationDeg(moon[h], target.geocentric(start.add(Duration(hours: h))));
    var h = 0;
    while (h <= hours) {
      if (geoSep(h) > 1.8) {
        h++;
        continue;
      }
      var last = h;
      while (last < hours && geoSep(last + 1) <= 1.8) {
        last++;
      }
      final o = _fromTheGround(target, start.add(Duration(hours: h - 2)), start.add(Duration(hours: last + 2)),
          latDeg, lonDeg);
      if (o != null && !o.closest.isBefore(start)) out.add(o);
      h = last + 1;
    }
  }
  return out..sort((a, b) => a.closest.compareTo(b.closest));
}

Occultation? _fromTheGround(_Target target, DateTime from, DateTime to, double lat, double lon) {
  double sep(DateTime t) => equatorialSeparationDeg(moonTopocentric(t, lat, lon), target.fromTheGround(t, lat, lon));
  double radius(DateTime t) => math.asin(_k / moonTopocentric(t, lat, lon).distance) * 180 / math.pi;

  // Closest approach: every minute, then to the second.
  var best = from;
  var bestSep = double.infinity;
  for (var t = from; !t.isAfter(to); t = t.add(const Duration(minutes: 1))) {
    final s = sep(t);
    if (s < bestSep) (best, bestSep) = (t, s);
  }
  var lo = best.subtract(const Duration(minutes: 1)), hi = best.add(const Duration(minutes: 1));
  while (hi.difference(lo).inMilliseconds > 500) {
    final a = lo.add(hi.difference(lo) * (1 / 3)), b = lo.add(hi.difference(lo) * (2 / 3));
    if (sep(a) < sep(b)) {
      hi = b;
    } else {
      lo = a;
    }
  }
  final closest = lo.add(hi.difference(lo) ~/ 2);
  final minSep = sep(closest), r = radius(closest);

  final p = target.planet;
  final disk = p == null ? 0.0 : _diskRadiusDeg(p, closest);
  final margin = p == null ? occultationStarMarginDeg : occultationPlanetMarginDeg;
  final error = p == null ? _starErrorDeg : _planetErrorDeg;
  if (minSep > r + margin + disk) return null;
  final covered = minSep <= r - margin - disk;

  // The edge crossings, to the second.
  DateTime crossing(DateTime inside, DateTime outside) {
    var a = inside, b = outside;
    while (b.difference(a).abs().inMilliseconds > 500) {
      final m = a.add(b.difference(a) ~/ 2);
      if (sep(m) < radius(m)) {
        a = m;
      } else {
        b = m;
      }
    }
    return a.add(b.difference(a) ~/ 2);
  }

  DateTime? disappears, reappears;
  var plusMinus = Duration.zero;
  if (covered) {
    const reach = Duration(hours: 2);
    for (final (edge, goingIn) in [(crossing(closest, closest.subtract(reach)), true), (crossing(closest, closest.add(reach)), false)]) {
      // The ± is the position error over how fast the gap to the edge
      // closes there: slow near a graze, ~0.5′ a minute head on.
      const dt = Duration(seconds: 30);
      final rate = (sep(edge.add(dt)) - sep(edge.subtract(dt))).abs() / 60;
      final pm = Duration(seconds: (error / rate).ceil());
      if (pm > plusMinus) plusMinus = pm;
      if (!_seen(edge, lat, lon)) continue;
      if (goingIn) {
        disappears = edge;
      } else {
        reappears = edge;
      }
    }
    if (disappears == null && reappears == null) return null;
  } else if (!_seen(closest, lat, lon)) {
    return null;
  }
  return Occultation(
    body: target.name,
    isPlanet: p != null,
    covered: covered,
    closest: closest,
    closestSepDeg: minSep,
    moonRadiusDeg: r,
    plusMinus: plusMinus,
    disappears: disappears,
    reappears: reappears,
  );
}

bool _seen(DateTime t, double lat, double lon) =>
    sunAltitudeDeg(t, lat, lon) <= _maxSunAltDeg && moonHorizontal(t, lat, lon).altitudeDeg >= _minMoonAltDeg;

/// Half the planet's apparent width (degrees), Saturn's rings included.
double _diskRadiusDeg(Planet p, DateTime utc) {
  final km = switch (p) {
    Planet.mercury => 2440.0,
    Planet.venus => 6052.0,
    Planet.mars => 3396.0,
    Planet.jupiter => 71492.0,
    Planet.saturn => 136775.0,
  };
  return math.atan(km / (planetEquatorial(p, utc).distance * 149597870.7)) * 180 / math.pi;
}
