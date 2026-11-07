/// Full Moons and moonrises, for the full-Moon moonrise alert. Pure Dart.
///
/// Checked against USNO full-Moon times and moonrises and JPL Horizons
/// distances in test/domain/moon_times_test.dart.
library;

import 'astro.dart';
import 'tonight.dart' show horizonCrossings;

/// A full Moon closer than this (km) is called a supermoon. Roughly the
/// closest tenth of full Moons; there's no official line.
const supermoonMaxKm = 360000.0;

class FullMoon {
  const FullMoon(this.at, this.distanceKm);

  /// The instant of full Moon (UTC).
  final DateTime at;

  /// Earth-centre to Moon-centre distance at [at].
  final double distanceKm;

  bool get supermoon => distanceKm < supermoonMaxKm;
}

/// Every full Moon in [from, to).
List<FullMoon> fullMoonsBetween(DateTime from, DateTime to) {
  // −180…180, rising through 0 at full Moon (it gains ~12° a day). The jump
  // from +180 to −180 is new Moon, not a crossing.
  double gap(DateTime t) => moonLongitudeFromSunDeg(t) - 180;
  const step = Duration(hours: 6);
  final out = <FullMoon>[];
  var t0 = from.toUtc();
  var g0 = gap(t0);
  while (t0.isBefore(to)) {
    final t1 = t0.add(step);
    final g1 = gap(t1);
    if (g0 < 0 && g1 >= 0 && g1 - g0 < 90) {
      var lo = t0, hi = t1;
      while (hi.difference(lo) > const Duration(seconds: 1)) {
        final mid = lo.add(Duration(microseconds: hi.difference(lo).inMicroseconds ~/ 2));
        if (gap(mid) < 0) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      if (!lo.isBefore(from.toUtc()) && lo.isBefore(to.toUtc())) out.add(FullMoon(lo, moonDistanceKm(lo)));
    }
    t0 = t1;
    g0 = g1;
  }
  return out;
}

/// Moonrises and moonsets in [from, to): when the top of the Moon crosses a
/// flat horizon, with the usual 34′ of refraction (USNO's definition).
List<({DateTime t, bool rising})> moonHorizonCrossings(DateTime from, DateTime to, double lat, double lon) {
  // moonHorizontal is already topocentric, so the centre is one refraction
  // plus one radius below the horizon.
  double alt(DateTime t) => moonHorizontal(t, lat, lon).altitudeDeg + 34 / 60 + moonRadiusDeg(t, 0);
  return horizonCrossings(alt, from, to);
}

/// Moonrises in [from, to), with where on the horizon.
List<({DateTime at, double azimuthDeg})> moonrisesBetween(DateTime from, DateTime to, double lat, double lon) => [
      for (final c in moonHorizonCrossings(from, to, lat, lon))
        if (c.rising) (at: c.t, azimuthDeg: moonHorizontal(c.t, lat, lon).azimuthDeg),
    ];
