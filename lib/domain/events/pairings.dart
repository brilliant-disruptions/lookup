/// Close pairings of the Moon and bright planets in the evening or morning
/// sky: the "what's that bright pair?" nights people photograph.
library;

import '../models/sky_event.dart';
import '../sky/astro.dart';
import '../sky/sun.dart';

class _Body {
  const _Body(this.label, this.position);
  final String label;
  final Horizontal Function(DateTime) position;
}

/// One event per pair per twilight, at two bodies are within [maxSepDeg]
/// (planet–planet) or [moonSepDeg] (Moon–planet), both ≥ 10° up, sky dark-ish.
List<SkyEvent> pairingEvents({
  required DateTime now,
  required double latDeg,
  required double lonDeg,
  int days = 14,
  double maxSepDeg = 3,
  double moonSepDeg = 5,
}) {
  final bodies = <_Body>[
    _Body('Moon', (t) => moonHorizontal(t, latDeg, lonDeg)),
    for (final p in Planet.values) _Body(p.label, (t) => planetHorizontal(p, t, latDeg, lonDeg)),
  ];
  final out = <SkyEvent>[];
  final seen = <String>{};
  var cursor = now.toUtc();
  final limit = now.add(Duration(days: days));
  while (cursor.isBefore(limit)) {
    final w = nextDarkWindow(cursor, latDeg, lonDeg, within: const Duration(hours: 30), step: const Duration(minutes: 10));
    if (w == null) break;
    // Check just after dusk and just before dawn.
    for (final (at, label) in [(w.start.add(const Duration(minutes: 30)), 'evening'), (w.end.subtract(const Duration(minutes: 30)), 'morning')]) {
      if (at.isBefore(now) || at.isAfter(limit)) continue;
      final pos = {for (final b in bodies) b.label: b.position(at)};
      for (var i = 0; i < bodies.length; i++) {
        for (var j = i + 1; j < bodies.length; j++) {
          final a = bodies[i], b = bodies[j];
          final pa = pos[a.label]!, pb = pos[b.label]!;
          if (pa.altitudeDeg < 10 || pb.altitudeDeg < 10) continue;
          final sep = separationDeg(pa, pb);
          final cap = a.label == 'Moon' || b.label == 'Moon' ? moonSepDeg : maxSepDeg;
          if (sep > cap) continue;
          final day = '${at.toUtc().year}-${at.toUtc().month}-${at.toUtc().day}';
          final key = '${a.label}-${b.label}-$day';
          if (!seen.add(key)) continue;
          final midAz = (pa.azimuthDeg + pb.azimuthDeg) / 2;
          final midAlt = (pa.altitudeDeg + pb.altitudeDeg) / 2;
          out.add(SkyEvent(
            id: 'pair:$key-$label',
            type: SkyEventType.planetPairing,
            start: at,
            peak: at,
            end: at.add(const Duration(minutes: 60)),
            peakElevationDeg: midAlt,
            riseAzimuthDeg: midAz,
            peakAzimuthDeg: midAz,
            setAzimuthDeg: midAz,
            details: {
              'bodies': [a.label, b.label],
              'separation': double.parse(sep.toStringAsFixed(1)),
              'when': label,
              'label': '${a.label} and ${b.label}',
            },
          ));
        }
      }
    }
    cursor = w.end.add(const Duration(hours: 1));
  }
  return out;
}
