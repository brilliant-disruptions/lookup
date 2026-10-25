/// "What else is up tonight": the brightest satellites passing over, from
/// Celestrak's ~150-object visual list. Never pushed; a list to browse.
library;

import '../models/sky_event.dart';
import '../orbit/omm.dart';
import '../passes/pass_predictor.dart';
import '../sky/brightness.dart';

/// Rough standard magnitudes (1000 km, half lit). The visual list doesn't
/// carry them, so we go by what each object is: these are spotter-grade,
/// and the UI says "about".
double standardMagnitudeFor(OmmRecord r) {
  final n = r.objectName.toUpperCase();
  if (r.noradCatId == Norad.iss) return StdMag.iss;
  if (r.noradCatId == Norad.tiangong || n.startsWith('CSS')) return StdMag.tiangong;
  if (n == 'HST') return 2.2;
  if (n.startsWith('SPACEMOBILE')) return 1.5; // AST BlueBirds: huge flat arrays
  if (n.startsWith('SL-16 R/B')) return 2.0; // Zenit second stages, 11 m long
  if (n == 'ENVISAT') return 3.0;
  if (n.contains('R/B')) return 3.2;
  return 3.6;
}

/// Plain-English name: "Hubble Space Telescope", "Zenit rocket stage".
String friendlySatelliteName(OmmRecord r) {
  final n = r.objectName.trim();
  final u = n.toUpperCase();
  if (r.noradCatId == Norad.iss) return 'Space station (ISS)';
  if (r.noradCatId == Norad.tiangong || u.startsWith('CSS')) return 'Tiangong';
  if (u == 'HST') return 'Hubble Space Telescope';
  if (u.startsWith('SPACEMOBILE-')) return 'BlueBird ${int.tryParse(u.substring(12)) ?? ''} (AST SpaceMobile)'.replaceAll('  ', ' ');
  const stages = {
    'SL-16': 'Zenit', 'SL-8': 'Kosmos-3M', 'SL-3': 'Vostok', 'SL-4': 'Soyuz', 'SL-6': 'Molniya',
    'SL-12': 'Proton', 'SL-14': 'Tsyklon', 'CZ-2C': 'Long March 2C', 'CZ-2D': 'Long March 2D',
    'CZ-4B': 'Long March 4B', 'CZ-8A': 'Long March 8A', 'H-2A': 'H-IIA',
  };
  if (u.contains('R/B')) {
    final base = n.substring(0, u.indexOf('R/B')).trim();
    return '${stages[base.toUpperCase()] ?? _titleCase(base)} rocket stage';
  }
  return _titleCase(n);
}

String _titleCase(String s) => s.split(' ').map((w) {
      if (w.length <= 4 || RegExp(r'\d').hasMatch(w)) return w; // acronyms, designators
      return w[0] + w.substring(1).toLowerCase();
    }).join(' ');

/// Visible passes between [from] and [to] brighter than [maxMagnitude],
/// brightest first, at most [limit]. Stations are left out: they have their
/// own alerts.
List<SkyEvent> brightTonight({
  required List<OmmRecord> records,
  required double latDeg,
  required double lonDeg,
  required DateTime from,
  required DateTime to,
  double maxMagnitude = 3.5,
  double minPeakElevationDeg = 20,
  int limit = 15,
}) {
  final predictor = PassPredictor(latitude: latDeg, longitude: lonDeg);
  final out = <SkyEvent>[];
  for (final r in records) {
    if (r.noradCatId == Norad.iss || r.noradCatId == Norad.tiangong || r.meanMotion < 11) continue;
    try {
      out.addAll(predictor.predict(
        record: r,
        type: SkyEventType.satellitePass,
        from: from,
        to: to,
        minPeakElevationDeg: minPeakElevationDeg,
        stdMag: standardMagnitudeFor(r),
        idPrefix: 'sat:${r.noradCatId}',
        details: {'name': friendlySatelliteName(r)},
      ));
    } catch (_) {
      // A decayed or malformed record: skip it, keep the rest.
    }
  }
  double mag(SkyEvent e) => (e.details['magnitude'] as num?)?.toDouble() ?? 99;
  out.removeWhere((e) => mag(e) > maxMagnitude);
  out.sort((a, b) => mag(a).compareTo(mag(b)));
  return out.take(limit).toList()..sort((a, b) => a.start.compareTo(b.start));
}
