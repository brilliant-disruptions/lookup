/// Major meteor showers. Peaks are defined by solar longitude (IMO), so we
/// compute the date each year instead of shipping a calendar that goes stale.
library;

import 'dart:math' as math;

import '../models/sky_event.dart';
import '../sky/astro.dart';
import '../sky/sun.dart';

class MeteorShower {
  const MeteorShower(this.name, this.code, {required this.solarLongitude, required this.zhr, required this.raDeg, required this.decDeg});
  final String name;
  final String code;
  final double solarLongitude; // degrees, J2000, IMO maximum
  final int zhr; // zenithal hourly rate at maximum
  final double raDeg, decDeg; // radiant at maximum
}

/// IMO 2026/2027 calendar values for the major showers.
const majorShowers = <MeteorShower>[
  MeteorShower('Quadrantids', 'QUA', solarLongitude: 283.15, zhr: 110, raDeg: 230, decDeg: 49),
  MeteorShower('Lyrids', 'LYR', solarLongitude: 32.32, zhr: 18, raDeg: 271, decDeg: 34),
  MeteorShower('Eta Aquariids', 'ETA', solarLongitude: 45.5, zhr: 50, raDeg: 338, decDeg: -1),
  MeteorShower('Perseids', 'PER', solarLongitude: 140.0, zhr: 100, raDeg: 48, decDeg: 58),
  MeteorShower('Draconids', 'DRA', solarLongitude: 195.4, zhr: 10, raDeg: 262, decDeg: 54),
  MeteorShower('Orionids', 'ORI', solarLongitude: 208.0, zhr: 20, raDeg: 95, decDeg: 16),
  MeteorShower('Leonids', 'LEO', solarLongitude: 235.27, zhr: 15, raDeg: 152, decDeg: 22),
  MeteorShower('Geminids', 'GEM', solarLongitude: 262.2, zhr: 150, raDeg: 112, decDeg: 33),
  MeteorShower('Ursids', 'URS', solarLongitude: 270.7, zhr: 10, raDeg: 217, decDeg: 76),
];

double _norm(double x) => ((x % 360) + 360) % 360;

/// UTC instant when the Sun reaches [targetLonDeg] next after [after].
DateTime solarLongitudeTime(double targetLonDeg, DateTime after) {
  // ~0.9856°/day. Step forward then bisect.
  var t = after.toUtc();
  final need = _norm(targetLonDeg - solarLongitudeDeg(t));
  t = t.add(Duration(minutes: (need / 0.9856 * 1440).round()));
  // Newton refine.
  for (var i = 0; i < 6; i++) {
    var diff = _norm(targetLonDeg - solarLongitudeDeg(t));
    if (diff > 180) diff -= 360;
    t = t.add(Duration(seconds: (diff / 0.9856 * 86400).round()));
  }
  return t;
}

/// Meteor-shower nights within [window] of [now] at a location. One event per
/// shower: the dark hours of the peak night, scored by expected visible rate.
List<SkyEvent> meteorShowerEvents({
  required DateTime now,
  required double latDeg,
  required double lonDeg,
  Duration window = const Duration(days: 30),
  int minZhr = 15,
}) {
  final out = <SkyEvent>[];
  for (final s in majorShowers) {
    if (s.zhr < minZhr) continue;
    final peak = solarLongitudeTime(s.solarLongitude, now.subtract(const Duration(days: 1)));
    if (peak.isAfter(now.add(window))) continue;
    // The local night containing (or nearest) the peak.
    final night = nextDarkWindow(peak.subtract(const Duration(hours: 18)), latDeg, lonDeg,
        within: const Duration(hours: 36), step: const Duration(minutes: 10));
    if (night == null) continue;
    if (night.end.isBefore(now)) continue;
    // Best hour: radiant highest while dark.
    var best = night.start;
    var bestAlt = -90.0;
    for (var t = night.start; t.isBefore(night.end); t = t.add(const Duration(minutes: 20))) {
      final alt = toHorizontal(Equatorial(s.raDeg, s.decDeg, 1), t, latDeg, lonDeg).altitudeDeg;
      if (alt > bestAlt) {
        bestAlt = alt;
        best = t;
      }
    }
    if (bestAlt < 15) continue; // radiant never gets up: few meteors here
    final moon = moonIllumination(best);
    final moonAlt = moonHorizontal(best, latDeg, lonDeg).altitudeDeg;
    final moonPenalty = moonAlt > 0 ? (1 - 0.7 * moon) : 1.0;
    final sinAlt = _sinDeg(bestAlt);
    final perHour = (s.zhr * sinAlt * moonPenalty * 0.6).round(); // 0.6: suburban sky
    // Tap in the evening ("tonight"), not at 2 AM inside quiet hours.
    final evening = night.start.add(const Duration(hours: 1));
    final start = evening.isBefore(best) ? evening : best;
    final end = night.end;
    final radiant = toHorizontal(Equatorial(s.raDeg, s.decDeg, 1), best, latDeg, lonDeg);
    out.add(SkyEvent(
      id: 'meteor-${s.code}:${peak.year}',
      type: SkyEventType.meteorShower,
      start: start,
      peak: best,
      end: end.isBefore(best) ? best : end,
      peakElevationDeg: bestAlt,
      riseAzimuthDeg: radiant.azimuthDeg,
      peakAzimuthDeg: radiant.azimuthDeg,
      setAzimuthDeg: radiant.azimuthDeg,
      details: {
        'shower': s.name,
        'zhr': s.zhr,
        'perHour': perHour,
        'moonIllumination': double.parse(moon.toStringAsFixed(2)),
        'moonUp': moonAlt > 0,
      },
    ));
  }
  return out;
}

double _sinDeg(double d) => math.sin(d * math.pi / 180);
