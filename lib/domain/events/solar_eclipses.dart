/// Solar eclipses, as seen from where you are: whether the Moon covers any
/// of the Sun here, how much at most and when, and whether you're inside
/// the path of totality (or annularity). Pure.
///
/// Local circumstances come from NASA's Besselian elements for each eclipse
/// ([besselianElements]) by the standard method (Explanatory Supplement;
/// Meeus, Elements of Solar Eclipses). That's good to seconds and to the
/// 1–2 km the Moon's mountainous edge allows, so "total" is still only said
/// with a margin: within a few km of the edge, or just outside it, it says
/// "near the path" and points at official maps. Never a false totality.
library;

import 'dart:math' as math;

import '../models/sky_event.dart';
import 'besselian_elements.dart';

export 'besselian_elements.dart' show BesselianElements, besselianElements;

enum LocalEclipseKind {
  /// The Moon covers part of the Sun.
  partial,

  /// At or just outside the edge of the path of totality or annularity: a
  /// short drive could change everything. Check an official map.
  nearPath,

  /// Inside the path of totality, with margin.
  total,

  /// Inside the path of annularity (a ring of Sun), with margin.
  annular,
}

class LocalSolarEclipse {
  const LocalSolarEclipse({
    required this.kind,
    required this.start,
    required this.greatest,
    required this.end,
    required this.magnitude,
    required this.obscuration,
    required this.sunAltitudeDeg,
    required this.sunAzimuthDeg,
    this.centralStart,
    this.centralEnd,
  });

  final LocalEclipseKind kind;

  /// First and last moments the Moon is on the Sun with the Sun up here
  /// (so a sunrise or sunset eclipse starts or ends at the horizon).
  final DateTime start;
  final DateTime greatest;
  final DateTime end;

  /// Fraction of the Sun's diameter covered at greatest (≥ 1 when total).
  final double magnitude;

  /// Fraction of the Sun's area covered at greatest, 0–1.
  final double obscuration;
  final double sunAltitudeDeg;
  final double sunAzimuthDeg;

  /// Totality or annularity (second to third contact), when [kind] is
  /// total or annular.
  final DateTime? centralStart;
  final DateTime? centralEnd;

  Duration? get centralDuration => centralStart == null ? null : centralEnd!.difference(centralStart!);
}

/// Inside the path by less than this (Earth radii, ≈3 km) isn't promised.
const _insideMargin = 0.0005;

/// Outside the path by less than this (≈25 km) is "near the path".
const _nearMargin = 0.004;

const _deg = math.pi / 180;

double _poly(List<double> c, double t) {
  var v = 0.0, p = 1.0;
  for (final k in c) {
    v += k * p;
    p *= t;
  }
  return v;
}

/// Area of the Sun's disk covered, from the magnitude [m] and the ratio of
/// apparent diameters Moon / Sun [a]: the overlap of two circles, the Sun's
/// radius 1, the Moon's [a], their centres 1 + a − 2m apart.
double obscurationFor(double m, double a) {
  final d = 1 + a - 2 * m;
  if (d >= 1 + a) return 0;
  if (d <= (a - 1).abs()) return a >= 1 ? 1 : a * a;
  final a1 = math.acos((d * d + 1 - a * a) / (2 * d));
  final a2 = a * a * math.acos((d * d + a * a - 1) / (2 * d * a));
  final a3 = 0.5 * math.sqrt((-d + 1 + a) * (d + 1 - a) * (d - 1 + a) * (d + 1 + a));
  return ((a1 + a2 - a3) / math.pi).clamp(0.0, 1.0);
}

/// The shadow relative to the observer at [t] hours from t0.
({double delta, double l1, double l2, double zeta, double h, double dDeg}) _shadow(
  BesselianElements e,
  double t,
  double rhoSin,
  double rhoCos,
  double lonDeg,
) {
  final x = _poly(e.x, t), y = _poly(e.y, t), d = _poly(e.d, t) * _deg;
  final l1 = _poly(e.l1, t), l2 = _poly(e.l2, t);
  // Hour angle of the shadow axis at the observer (east longitude positive).
  final h = (_poly(e.mu, t) + lonDeg - 0.00417807 * e.deltaT) * _deg;
  final xi = rhoCos * math.sin(h);
  final eta = rhoSin * math.cos(d) - rhoCos * math.cos(h) * math.sin(d);
  final zeta = rhoSin * math.sin(d) + rhoCos * math.cos(h) * math.cos(d);
  final u = x - xi, v = y - eta;
  return (delta: math.sqrt(u * u + v * v), l1: l1 - zeta * e.tanF1, l2: l2 - zeta * e.tanF2, zeta: zeta, h: h, dDeg: d / _deg);
}

/// Local circumstances of eclipse [e] at [lat]/[lon], or null when none of
/// it is visible here (the Moon misses the Sun here, or it's below the
/// horizon throughout).
LocalSolarEclipse? localSolarEclipse(BesselianElements e, double lat, double lon) {
  final u = math.atan(0.99664719 * math.tan(lat * _deg));
  final rhoSin = 0.99664719 * math.sin(u), rhoCos = math.cos(u);
  DateTime at(double t) {
    final ms = ((e.t0 + t) * 3600 - e.deltaT) * 1000;
    return e.date.add(Duration(milliseconds: ms.round()));
  }

  // Minute by minute over the ±3 h the polynomials cover.
  double? first, last, best;
  var bestDelta = double.infinity;
  bool visible(double t) {
    final s = _shadow(e, t, rhoSin, rhoCos, lon);
    return s.zeta > -0.01 && s.delta < s.l1;
  }

  for (var t = -3.0; t <= 3.0; t += 1 / 60) {
    final s = _shadow(e, t, rhoSin, rhoCos, lon);
    if (s.zeta <= -0.01 || s.delta >= s.l1) continue;
    first ??= t;
    last = t;
    if (s.delta < bestDelta) {
      bestDelta = s.delta;
      best = t;
    }
  }
  if (best == null) return null;
  // Refine greatest, and the first and last moments, to about a second.
  final coarse = best;
  for (var t = coarse - 1 / 60; t <= coarse + 1 / 60; t += 1 / 3600) {
    final s = _shadow(e, t, rhoSin, rhoCos, lon);
    if (s.zeta > -0.01 && s.delta < bestDelta) {
      bestDelta = s.delta;
      best = t;
    }
  }
  double edge(double inside, double outside) {
    var a = inside, b = outside;
    for (var i = 0; i < 30; i++) {
      final m = (a + b) / 2;
      if (visible(m)) {
        a = m;
      } else {
        b = m;
      }
    }
    return a;
  }

  first = edge(first!, first - 1 / 60);
  last = edge(last!, last + 1 / 60);

  final g = _shadow(e, best!, rhoSin, rhoCos, lon);
  final pathHalf = g.l2.abs();
  final kind = bestDelta < pathHalf - _insideMargin
      ? (g.l2 < 0 ? LocalEclipseKind.total : LocalEclipseKind.annular)
      : bestDelta < pathHalf + _nearMargin
      ? LocalEclipseKind.nearPath
      : LocalEclipseKind.partial;

  DateTime? cStart, cEnd;
  if (kind == LocalEclipseKind.total || kind == LocalEclipseKind.annular) {
    bool central(double t) {
      final s = _shadow(e, t, rhoSin, rhoCos, lon);
      return s.delta < s.l2.abs();
    }

    double contact(double inside, double outside) {
      var a = inside, b = outside;
      for (var i = 0; i < 40; i++) {
        final m = (a + b) / 2;
        if (central(m)) {
          a = m;
        } else {
          b = m;
        }
      }
      return a;
    }

    cStart = at(contact(best, best - 0.2));
    cEnd = at(contact(best, best + 0.2));
  }

  final magnitude = (g.l1 - bestDelta) / (g.l1 + g.l2);
  final ratio = (g.l1 - g.l2) / (g.l1 + g.l2);
  // Sun's altitude and azimuth from the shadow's hour angle and declination.
  final latR = lat * _deg, dR = g.dDeg * _deg;
  final sinAlt = math.sin(latR) * math.sin(dR) + math.cos(latR) * math.cos(dR) * math.cos(g.h);
  final alt = math.asin(sinAlt.clamp(-1.0, 1.0)) / _deg;
  final az =
      (math.atan2(-math.cos(dR) * math.sin(g.h), math.sin(dR) * math.cos(latR) - math.cos(dR) * math.sin(latR) * math.cos(g.h)) / _deg +
          360) %
      360;

  return LocalSolarEclipse(
    kind: kind,
    start: at(first),
    greatest: at(best),
    end: at(last),
    magnitude: magnitude,
    obscuration: obscurationFor(magnitude, ratio),
    sunAltitudeDeg: alt,
    sunAzimuthDeg: az,
    centralStart: cStart,
    centralEnd: cEnd,
  );
}

/// Solar eclipses visible from here within [window], as events. Ones where
/// the Moon only nicks the Sun (under 10% of its area) are left out: even
/// through eclipse glasses they're easy to miss, which would read as a false
/// alarm.
List<SkyEvent> solarEclipseEvents({
  required DateTime now,
  required double latDeg,
  required double lonDeg,
  Duration window = const Duration(days: 60),
}) {
  final u = now.toUtc();
  final out = <SkyEvent>[];
  for (final e in besselianElements) {
    if (e.date.isBefore(u.subtract(const Duration(days: 1))) || e.date.isAfter(u.add(window))) continue;
    final l = localSolarEclipse(e, latDeg, lonDeg);
    if (l == null || l.obscuration < 0.1 || l.end.isBefore(u)) continue;
    out.add(
      SkyEvent(
        id: 'solar:${e.date.toIso8601String().substring(0, 10)}',
        type: SkyEventType.solarEclipse,
        start: l.start,
        peak: l.greatest,
        end: l.end,
        peakElevationDeg: l.sunAltitudeDeg,
        riseAzimuthDeg: l.sunAzimuthDeg,
        peakAzimuthDeg: l.sunAzimuthDeg,
        setAzimuthDeg: l.sunAzimuthDeg,
        details: {
          'kind': l.kind.name,
          'obscuration': double.parse(l.obscuration.toStringAsFixed(3)),
          'magnitude': double.parse(l.magnitude.toStringAsFixed(3)),
          if (l.centralStart != null) 'centralStart': l.centralStart!.toIso8601String(),
          if (l.centralEnd != null) 'centralEnd': l.centralEnd!.toIso8601String(),
        },
      ),
    );
  }
  return out;
}

/// "92% of the Sun covered", "Total eclipse here: 2 min 41 s of darkness".
String solarEclipseHeadline(SkyEvent e) {
  final kind = e.details['kind'];
  final pct = (((e.details['obscuration'] as num?) ?? 0) * 100).floor();
  final cs = e.details['centralStart'], ce = e.details['centralEnd'];
  String dur() {
    if (cs is! String || ce is! String) return '';
    final d = DateTime.parse(ce).difference(DateTime.parse(cs));
    return '${d.inMinutes} min ${d.inSeconds % 60} s';
  }

  return switch (kind) {
    'total' => 'Total eclipse here: ${dur()} of darkness',
    'annular' => 'Ring of fire here for ${dur()}',
    'nearPath' => '$pct% covered, right at the edge of the path',
    _ => '$pct% of the Sun covered',
  };
}
