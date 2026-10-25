/// Lunar eclipses 2026–2030 (NASA GSFC eclipse catalog, Espenak & Meeus).
/// A lunar eclipse is visible from wherever the Moon is up, so visibility is
/// just "Moon above the horizon at greatest eclipse, and the sky dark".
library;

import '../models/sky_event.dart';
import '../sky/astro.dart';
import '../sky/sun.dart';

enum EclipseKind { total, partial, penumbral }

class LunarEclipse {
  const LunarEclipse(this.greatest, this.kind, this.umbralMagnitude);
  final DateTime greatest;
  final EclipseKind kind;
  final double umbralMagnitude;
}

final lunarEclipses = <LunarEclipse>[
  LunarEclipse(DateTime.utc(2026, 3, 3, 11, 34), EclipseKind.total, 1.1507),
  LunarEclipse(DateTime.utc(2026, 8, 28, 4, 13), EclipseKind.partial, 0.9299),
  LunarEclipse(DateTime.utc(2027, 2, 20, 23, 13), EclipseKind.penumbral, -0.0569),
  LunarEclipse(DateTime.utc(2027, 7, 18, 16, 3), EclipseKind.penumbral, -1.0680),
  LunarEclipse(DateTime.utc(2027, 8, 17, 7, 14), EclipseKind.penumbral, -0.5254),
  LunarEclipse(DateTime.utc(2028, 1, 12, 4, 13), EclipseKind.partial, 0.0662),
  LunarEclipse(DateTime.utc(2028, 7, 6, 18, 20), EclipseKind.partial, 0.3892),
  LunarEclipse(DateTime.utc(2028, 12, 31, 16, 52), EclipseKind.total, 1.2463),
  LunarEclipse(DateTime.utc(2029, 6, 26, 3, 22), EclipseKind.total, 1.8436),
  LunarEclipse(DateTime.utc(2029, 12, 20, 22, 42), EclipseKind.total, 1.1174),
  LunarEclipse(DateTime.utc(2030, 6, 15, 18, 33), EclipseKind.partial, 0.5025),
  LunarEclipse(DateTime.utc(2030, 12, 9, 22, 28), EclipseKind.penumbral, -0.1628),
];

/// Visible total and partial eclipses within [window]. Penumbral eclipses
/// are skipped: most people can't tell anything happened, which would read
/// as a false alarm.
List<SkyEvent> lunarEclipseEvents({
  required DateTime now,
  required double latDeg,
  required double lonDeg,
  Duration window = const Duration(days: 60),
}) {
  final out = <SkyEvent>[];
  for (final e in lunarEclipses) {
    if (e.kind == EclipseKind.penumbral) continue;
    if (e.greatest.isBefore(now.subtract(const Duration(hours: 2))) || e.greatest.isAfter(now.add(window))) continue;
    final moon = moonHorizontal(e.greatest, latDeg, lonDeg);
    if (moon.altitudeDeg < 5) continue;
    if (sunAltitudeDeg(e.greatest, latDeg, lonDeg) > -6) continue;
    final half = e.kind == EclipseKind.total ? const Duration(minutes: 90) : const Duration(minutes: 60);
    out.add(SkyEvent(
      id: 'eclipse:${e.greatest.toIso8601String()}',
      type: SkyEventType.lunarEclipse,
      start: e.greatest.subtract(half),
      peak: e.greatest,
      end: e.greatest.add(half),
      peakElevationDeg: moon.altitudeDeg,
      riseAzimuthDeg: moon.azimuthDeg,
      peakAzimuthDeg: moon.azimuthDeg,
      setAzimuthDeg: moon.azimuthDeg,
      details: {
        'kind': e.kind.name,
        'magnitude': e.umbralMagnitude,
        'label': e.kind == EclipseKind.total ? 'Total lunar eclipse' : 'Partial lunar eclipse',
      },
    ));
  }
  return out;
}
