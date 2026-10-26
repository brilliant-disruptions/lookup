/// Everything up tonight, from one place on Earth: planets, the Moon,
/// constellations and showpieces, each with its best time and a "can I see
/// it?" verdict that includes the weather. Pure Dart; all computed here.
library;

import '../weather/cloud_forecast.dart';
import 'astro.dart';
import 'catalog.dart';
import 'sun.dart';
import 'visibility.dart';

/// Altitude-crossing times of [altAt] through [h0] in [from, to].
List<({DateTime t, bool rising})> horizonCrossings(
  double Function(DateTime) altAt,
  DateTime from,
  DateTime to, {
  double h0 = 0,
  Duration step = const Duration(minutes: 10),
}) {
  final out = <({DateTime t, bool rising})>[];
  var t0 = from.toUtc();
  var a0 = altAt(t0) - h0;
  while (t0.isBefore(to)) {
    final t1 = t0.add(step);
    final a1 = altAt(t1) - h0;
    if ((a0 < 0) != (a1 < 0)) {
      var lo = t0, hi = t1, alo = a0;
      while (hi.difference(lo) > const Duration(seconds: 30)) {
        final mid = lo.add(Duration(microseconds: hi.difference(lo).inMicroseconds ~/ 2));
        final am = altAt(mid) - h0;
        if ((alo < 0) == (am < 0)) {
          lo = mid;
          alo = am;
        } else {
          hi = mid;
        }
      }
      out.add((t: hi, rising: a1 >= 0));
    }
    t0 = t1;
    a0 = a1;
  }
  return out;
}

/// The stretch of tonight that's dark enough to look (sun ≤ −6°): from now if
/// it's already dark, else from dusk; to dawn. Null in polar summer.
({DateTime start, DateTime end})? tonightWindow(DateTime now, double lat, double lon) =>
    nextDarkWindow(now, lat, lon, within: const Duration(hours: 30), step: const Duration(minutes: 5));

/// One object's night: when it's best, and whether you'll see it then.
class Sighting {
  const Sighting({
    required this.best,
    required this.altDeg,
    required this.azDeg,
    required this.verdict,
    this.visibleFrom,
    this.visibleTo,
  });

  /// When it's best placed (highest, darkest, clearest) tonight.
  final DateTime best;
  final double altDeg;
  final double azDeg;
  final Seeability verdict;

  /// Span of tonight when it's up and dark enough (ignoring weather).
  final DateTime? visibleFrom;
  final DateTime? visibleTo;
}

/// Samples [window] every 15 minutes and picks the best moment: a "yes"
/// verdict first, then higher in the sky, then fewer clouds.
Sighting? bestSighting({
  required Horizontal Function(DateTime) position,
  required double mag,
  required ({DateTime start, DateTime end}) window,
  required double lat,
  required double lon,
  required SkyDarkness darkness,
  CloudForecast? weather,
  bool diffuse = false,
}) {
  Sighting? best;
  double bestScore = -1e9;
  DateTime? from, to;
  for (var t = window.start; !t.isAfter(window.end); t = t.add(const Duration(minutes: 15))) {
    final h = position(t);
    if (h.altitudeDeg <= 0) continue;
    final c = SkyConditions.at(t, lat, lon, weather: weather);
    final v = canSee(altDeg: h.altitudeDeg, mag: mag, c: c, darkness: darkness, diffuse: diffuse);
    final skyOk = v != Seeability.tooFaint && v != Seeability.twilight && v != Seeability.moonlit;
    if (skyOk && h.altitudeDeg >= 8) {
      from ??= t;
      to = t;
    }
    // Prefer properly dark sky over a high-but-twilit moment.
    final glow = c.sunAltDeg > -12 ? (c.sunAltDeg + 12) * 3 : 0.0;
    final score = (v.yes ? 1000 : 0) + h.altitudeDeg - (c.cloudPercent ?? 0) * 0.3 - glow;
    if (score > bestScore) {
      bestScore = score;
      best = Sighting(best: t, altDeg: h.altitudeDeg, azDeg: h.azimuthDeg, verdict: v);
    }
  }
  if (best == null) return null;
  return Sighting(
    best: best.best,
    altDeg: best.altDeg,
    azDeg: best.azDeg,
    verdict: best.verdict,
    visibleFrom: from,
    visibleTo: to,
  );
}

class PlanetTonight {
  const PlanetTonight({
    required this.planet,
    required this.magnitude,
    required this.elongationDeg,
    required this.evening,
    this.sighting,
    this.rise,
    this.set,
    this.whyNot,
  });
  final Planet planet;
  final double magnitude;
  final double elongationDeg;
  final bool evening;
  final Sighting? sighting;
  final DateTime? rise;
  final DateTime? set;

  /// Plain reason when it can't be seen tonight at all.
  final String? whyNot;

  bool get visible => sighting != null && sighting!.verdict.yes;
}

List<PlanetTonight> planetsTonight({
  required DateTime now,
  required double lat,
  required double lon,
  required SkyDarkness darkness,
  CloudForecast? weather,
}) {
  final night = _eveningToDawn(now, lat, lon);
  return [
    for (final p in Planet.values) _planet(p, now, night, lat, lon, darkness, weather),
  ]..sort((a, b) {
      if (a.visible != b.visible) return a.visible ? -1 : 1;
      return a.magnitude.compareTo(b.magnitude);
    });
}

/// Planets show in twilight, so "tonight" for them starts at sun −3°.
({DateTime start, DateTime end}) _eveningToDawn(DateTime now, double lat, double lon) {
  final w = nextDarkWindow(now, lat, lon, within: const Duration(hours: 30), step: const Duration(minutes: 5));
  if (w == null) return (start: now.toUtc(), end: now.toUtc().add(const Duration(hours: 12)));
  final start = w.start.isAfter(now) ? w.start.subtract(const Duration(minutes: 25)) : now.toUtc();
  return (start: start, end: w.end.add(const Duration(minutes: 25)));
}

PlanetTonight _planet(Planet p, DateTime now, ({DateTime start, DateTime end}) night, double lat, double lon,
    SkyDarkness darkness, CloudForecast? weather) {
  final mid = night.start.add(Duration(microseconds: night.end.difference(night.start).inMicroseconds ~/ 2));
  final mag = planetMagnitude(p, mid);
  final elong = planetElongationDeg(p, mid);
  final evening = planetIsEvening(p, mid);
  Horizontal pos(DateTime t) => planetHorizontal(p, t, lat, lon);
  final crossings = horizonCrossings((t) => pos(t).altitudeDeg, now.subtract(const Duration(hours: 2)),
      now.add(const Duration(hours: 26)), h0: -0.57);
  DateTime? rise, set;
  for (final c in crossings) {
    if (c.rising && rise == null && c.t.isAfter(now.subtract(const Duration(hours: 2)))) rise = c.t;
    if (!c.rising && set == null && c.t.isAfter(now)) set = c.t;
  }
  final s = bestSighting(position: pos, mag: mag, window: night, lat: lat, lon: lon, darkness: darkness, weather: weather);
  String? whyNot;
  if (s == null || s.visibleFrom == null) {
    whyNot = elong < 12
        ? 'Too close to the Sun right now'
        : elong < 35
            ? 'Lost in the twilight glow tonight'
            : 'Only up in daylight this month';
  }
  return PlanetTonight(
    planet: p,
    magnitude: double.parse(mag.toStringAsFixed(1)),
    elongationDeg: elong,
    evening: evening,
    sighting: whyNot == null ? s : null,
    rise: rise,
    set: set,
    whyNot: whyNot,
  );
}

enum MoonPhase {
  newMoon('New Moon'),
  waxingCrescent('Waxing crescent'),
  firstQuarter('First quarter'),
  waxingGibbous('Waxing gibbous'),
  full('Full Moon'),
  waningGibbous('Waning gibbous'),
  lastQuarter('Last quarter'),
  waningCrescent('Waning crescent');

  const MoonPhase(this.label);
  final String label;
}

MoonPhase moonPhase(DateTime utc) {
  final illum = moonIllumination(utc);
  final m = moonEquatorial(utc), s = sunEquatorial(utc);
  final waxing = ((m.raDeg - s.raDeg) % 360 + 360) % 360 < 180;
  if (illum < 0.03) return MoonPhase.newMoon;
  if (illum > 0.97) return MoonPhase.full;
  if (illum >= 0.45 && illum <= 0.55) return waxing ? MoonPhase.firstQuarter : MoonPhase.lastQuarter;
  if (illum < 0.5) return waxing ? MoonPhase.waxingCrescent : MoonPhase.waningCrescent;
  return waxing ? MoonPhase.waxingGibbous : MoonPhase.waningGibbous;
}

class MoonTonight {
  const MoonTonight({required this.phase, required this.illumination, required this.waxing, this.rise, this.set, this.sighting});
  final MoonPhase phase;
  final double illumination;
  final bool waxing;
  final DateTime? rise;
  final DateTime? set;
  final Sighting? sighting;
}

MoonTonight moonTonight({required DateTime now, required double lat, required double lon, CloudForecast? weather}) {
  final crossings = horizonCrossings((t) => moonHorizontal(t, lat, lon).altitudeDeg, now.subtract(const Duration(hours: 1)),
      now.add(const Duration(hours: 26)), h0: 0.125);
  DateTime? rise, set;
  for (final c in crossings) {
    if (c.rising && rise == null) rise = c.t;
    if (!c.rising && set == null && c.t.isAfter(now)) set = c.t;
  }
  final night = _eveningToDawn(now, lat, lon);
  final phase = moonPhase(now);
  final m = moonEquatorial(now), s = sunEquatorial(now);
  return MoonTonight(
    phase: phase,
    illumination: moonIllumination(now),
    waxing: ((m.raDeg - s.raDeg) % 360 + 360) % 360 < 180,
    rise: rise,
    set: set,
    sighting: bestSighting(
      position: (t) => moonHorizontal(t, lat, lon),
      mag: -10,
      window: night,
      lat: lat,
      lon: lon,
      darkness: SkyDarkness.city,
      weather: weather,
    ),
  );
}

class ConstellationTonight {
  const ConstellationTonight(this.constellation, this.sighting);
  final Constellation constellation;
  final Sighting sighting;
}

/// Constellations worth finding tonight: the well-known ones (rank ≤ 2)
/// that climb above 25°, best placed first. Their brightness is their
/// brightest star's.
List<ConstellationTonight> constellationsTonight({
  required SkyCatalog catalog,
  required DateTime now,
  required double lat,
  required double lon,
  required SkyDarkness darkness,
  CloudForecast? weather,
  int maxRank = 2,
}) {
  final w = tonightWindow(now, lat, lon);
  if (w == null) return const [];
  // Judge them once it's properly dark (an hour after dusk, an hour before
  // dawn), hourly to keep it cheap: 88 constellations × ~10 samples.
  final darkStart = w.start.isAfter(now) ? w.start.add(const Duration(hours: 1)) : w.start;
  final darkEnd = w.end.subtract(const Duration(hours: 1));
  final night = darkEnd.isAfter(darkStart) ? (start: darkStart, end: darkEnd) : w;
  final out = <ConstellationTonight>[];
  for (final c in catalog.constellations.where((c) => c.rank <= maxRank)) {
    final brightest = _brightestIn(catalog, c);
    Horizontal pos(DateTime t) => c.center(t, lat, lon);
    var peak = night.start;
    var peakAlt = -90.0;
    for (var t = night.start; !t.isAfter(night.end); t = t.add(const Duration(hours: 1))) {
      final a = pos(t).altitudeDeg;
      if (a > peakAlt) {
        peakAlt = a;
        peak = t;
      }
    }
    if (peakAlt < 25) continue;
    final h = pos(peak);
    final cond = SkyConditions.at(peak, lat, lon, weather: weather);
    out.add(ConstellationTonight(
      c,
      Sighting(
        best: peak,
        altDeg: h.altitudeDeg,
        azDeg: h.azimuthDeg,
        verdict: canSee(altDeg: h.altitudeDeg, mag: brightest, c: cond, darkness: darkness),
      ),
    ));
  }
  out.sort((a, b) {
    final r = a.constellation.rank.compareTo(b.constellation.rank);
    return r != 0 ? r : b.sighting.altDeg.compareTo(a.sighting.altDeg);
  });
  return out;
}

double _brightestIn(SkyCatalog catalog, Constellation c) {
  // The stick-figure vertices are stars; match them to the catalog.
  var best = 6.0;
  for (final seg in c.lines) {
    for (final (ra, dec) in seg) {
      for (final s in catalog.stars) {
        if (s.mag >= best) break; // stars are sorted brightest first
        if ((s.raDeg - ra).abs() < 0.05 && (s.decDeg - dec).abs() < 0.05) {
          best = s.mag;
          break;
        }
      }
    }
  }
  return best;
}

class ShowpieceTonight {
  const ShowpieceTonight(this.showpiece, this.sighting);
  final Showpiece showpiece;
  final Sighting sighting;
}

/// Showpieces that get above 15° tonight, the ones you can see first.
List<ShowpieceTonight> showpiecesTonight({
  required DateTime now,
  required double lat,
  required double lon,
  required SkyDarkness darkness,
  CloudForecast? weather,
}) {
  final night = tonightWindow(now, lat, lon);
  if (night == null) return const [];
  final out = <ShowpieceTonight>[];
  for (final s in showpieces) {
    final sight = bestSighting(
      position: (t) => s.horizontal(t, lat, lon),
      // Binoculars reach ~2 magnitudes deeper, a small telescope ~4.
      mag: s.mag - switch (s.aid) { Aid.eyes => 0, Aid.binoculars => 2, Aid.telescope => 4 },
      window: night,
      lat: lat,
      lon: lon,
      darkness: darkness,
      weather: weather,
      diffuse: s.diffuse,
    );
    if (sight == null || sight.altDeg < 15) continue;
    out.add(ShowpieceTonight(s, sight));
  }
  out.sort((a, b) {
    if (a.sighting.verdict.yes != b.sighting.verdict.yes) return a.sighting.verdict.yes ? -1 : 1;
    return a.showpiece.mag.compareTo(b.showpiece.mag);
  });
  return out;
}

/// A planet's notable night: opposition (Mars, Jupiter, Saturn at their
/// biggest and brightest) or greatest elongation (Mercury and Venus as far
/// from the Sun as they get).
class PlanetHighlight {
  const PlanetHighlight({required this.planet, required this.date, required this.kind, required this.evening});
  final Planet planet;

  /// UTC noon of the day it happens.
  final DateTime date;
  final String kind; // 'opposition' | 'elongation'
  final bool evening;

  String get title => kind == 'opposition'
      ? '${planet.label} at its brightest'
      : '${planet.label} at its best ${evening ? 'after sunset' : 'before dawn'}';
}

/// Highlights in the next [days], soonest first. Scans daily (elongation
/// changes slowly; the day is what matters).
List<PlanetHighlight> planetHighlights(DateTime from, {int days = 400}) {
  final out = <PlanetHighlight>[];
  final start = DateTime.utc(from.year, from.month, from.day, 12);
  for (final p in Planet.values) {
    final outer = p != Planet.mercury && p != Planet.venus;
    double e(int i) => planetElongationDeg(p, start.add(Duration(days: i)));
    var prev = e(-1), cur = e(0);
    for (var i = 0; i <= days; i++) {
      final next = e(i + 1);
      if (cur >= prev && cur > next) {
        final when = start.add(Duration(days: i));
        if (outer ? cur > 170 : cur > 17) {
          out.add(PlanetHighlight(
            planet: p,
            date: when,
            kind: outer ? 'opposition' : 'elongation',
            evening: outer || planetIsEvening(p, when),
          ));
        }
      }
      prev = cur;
      cur = next;
    }
  }
  out.sort((a, b) => a.date.compareTo(b.date));
  return out;
}

/// Distance-free brightness comparison for a planet, for the copy.
String planetBrightnessWord(double mag) {
  if (mag <= -3.5) return 'dazzling, the brightest thing after the Moon';
  if (mag <= -1.5) return 'brighter than any star';
  if (mag <= 0.5) return 'as bright as the brightest stars';
  if (mag <= 2.0) return 'a steady, bright star';
  return 'a modest star';
}
