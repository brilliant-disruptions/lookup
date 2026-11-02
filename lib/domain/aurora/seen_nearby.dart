/// "Seen near you": when other LookUp users' "I can see it" reports are
/// enough to tell you the aurora is out right now. Pure Dart.
///
/// The reports come from the push relay (docs/seen-near-you.md; not built
/// yet). This file is the part that must never cry wolf, so it runs on the
/// phone and is tested here:
///
///  * Reports alone never confirm anything. The model has to find aurora
///    plausible at your geomagnetic latitude too (Kp within [CrowdRules.kpSlack]
///    of what's needed there), and it has to be dark and clear where you are.
///  * Several different people, from more than one place, recently, and not
///    all from much further toward the pole than you (aurora seen 250 km
///    nearer the pole says little about your sky).
///  * Reports carry a coarse cell (half a degree, ~55 km), never a position.
library;

import 'dart:math' as math;

import '../plan/where_to_go.dart' show bearingDeg, distanceKm;
import '../sky/direction.dart';
import '../sky/geomagnetic.dart';
import '../sky/sun.dart';
import 'aurora_rules.dart';

/// Size of the cells reports are snapped to, degrees.
const reportCellDeg = 0.5;

/// The centre of the cell a report from [latDeg], [lonDeg] is filed under:
/// all that ever leaves the phone about where you are.
({double lat, double lon}) reportCell(double latDeg, double lonDeg) {
  double snap(double v) => ((v / reportCellDeg).floorToDouble() + 0.5) * reportCellDeg;
  final lon = ((lonDeg + 180) % 360 + 360) % 360 - 180;
  return (lat: snap(latDeg.clamp(-89.99, 89.99)), lon: snap(lon));
}

enum SeenHow {
  /// With their own eyes.
  eye,

  /// Only on a phone camera (it sees faint aurora colour first).
  camera,
}

/// One "I can see it", as the relay hands it back.
class AuroraReport {
  const AuroraReport({
    required this.cellLat,
    required this.cellLon,
    required this.at,
    required this.how,
    required this.reporter,
  });

  /// The cell's centre ([reportCell]).
  final double cellLat, cellLon;
  final DateTime at;
  final SeenHow how;

  /// An opaque token per install, rotated daily: only for counting people
  /// once, never for following anyone.
  final String reporter;

  factory AuroraReport.fromJson(Map<String, Object?> j) => AuroraReport(
        cellLat: (j['la'] as num).toDouble(),
        cellLon: (j['lo'] as num).toDouble(),
        at: DateTime.parse(j['at'] as String).toUtc(),
        how: j['how'] == 'camera' ? SeenHow.camera : SeenHow.eye,
        reporter: j['r'] as String,
      );

  Map<String, Object?> toJson() =>
      {'la': cellLat, 'lo': cellLon, 'at': at.toUtc().toIso8601String(), 'how': how.name, 'r': reporter};
}

class CrowdRules {
  const CrowdRules({
    this.radiusKm = 250,
    this.window = const Duration(minutes: 20),
    this.freshest = const Duration(minutes: 10),
    this.minReporters = 4,
    this.minCells = 2,
    this.kpSlack = 1.5,
    this.polewardSlackDeg = 1.5,
    this.cloudyThreshold = 60,
  });

  /// How far away a report may be.
  final double radiusKm;

  /// How old the oldest counted report may be.
  final Duration window;

  /// At least one report this recent: it's still going on.
  final Duration freshest;

  /// Different people.
  final int minReporters;

  /// Different cells: no single crowd (or single prankster with friends).
  final int minCells;

  /// The crowd can confirm an aurora the Kp model would call a little
  /// short (it often is, south of the oval), but only by this much.
  final double kpSlack;

  /// Reports count only from up to this much further toward the pole
  /// (geomagnetic latitude) than you.
  final double polewardSlackDeg;

  final int cloudyThreshold;
}

class CrowdVerdict {
  const CrowdVerdict._({
    required this.confirmed,
    required this.reason,
    this.people = 0,
    this.byEye = 0,
    this.nearestKm,
    this.towardDeg,
  });

  final bool confirmed;

  /// Why not (or "go"): for logs and tests, not for the screen.
  final String reason;

  /// Different people counted, and how many of them saw it by eye.
  final int people, byEye;

  /// The nearest counted report, and which way it is from you.
  final double? nearestKm, towardDeg;

  /// "Aurora being seen 60 km north of you" — null unless confirmed.
  String? get headline {
    if (!confirmed || nearestKm == null || towardDeg == null) return null;
    final km = nearestKm! < 30 ? 'right around you' : '${(nearestKm! / 10).round() * 10} km ${compassWord(towardDeg!)} of you';
    return 'Aurora being seen $km';
  }

  /// "5 people in the last 20 minutes, 3 by eye. Face north, low."
  String? body(Duration window) {
    if (!confirmed) return null;
    final eye = byEye == people ? ', all by eye' : (byEye == 0 ? ', on their phone cameras' : ', $byEye by eye');
    return '$people people in the last ${window.inMinutes} minutes$eye. '
        'Get away from lights and face north, low in the sky. A phone camera shows colour your eyes may miss.';
  }

  static CrowdVerdict no(String reason) => CrowdVerdict._(confirmed: false, reason: reason);
}

/// Should we tell you, here at [latDeg], [lonDeg], that the aurora is
/// being seen near you right now?
CrowdVerdict crowdConfirms({
  required List<AuroraReport> reports,
  required DateTime now,
  required double latDeg,
  required double lonDeg,
  required double estimatedKp,
  int? cloudCoverPercent,
  CrowdRules rules = const CrowdRules(),
}) {
  final u = now.toUtc();
  // Your sky first: dark and clear, or there's nothing to go out for.
  if (!isDark(u, latDeg, lonDeg)) return CrowdVerdict.no('not dark');
  if (cloudCoverPercent != null && cloudCoverPercent > rules.cloudyThreshold) {
    return CrowdVerdict.no('cloudy $cloudCoverPercent%');
  }
  // The model has to agree it's possible here: reports alone never do it.
  final needed = kpNeededAt(latDeg, lonDeg);
  if (estimatedKp < needed - rules.kpSlack) {
    return CrowdVerdict.no('Kp ${estimatedKp.toStringAsFixed(1)} too far below ${needed.toStringAsFixed(1)}');
  }
  final myMag = geomagneticLatitudeDeg(latDeg, lonDeg).abs();
  final latest = <String, AuroraReport>{}; // one per person: their latest
  for (final r in reports) {
    final age = u.difference(r.at);
    if (age.isNegative || age > rules.window) continue;
    if (distanceKm(latDeg, lonDeg, r.cellLat, r.cellLon) > rules.radiusKm) continue;
    if (geomagneticLatitudeDeg(r.cellLat, r.cellLon).abs() > myMag + rules.polewardSlackDeg) continue;
    final prev = latest[r.reporter];
    if (prev == null || r.at.isAfter(prev.at)) latest[r.reporter] = r;
  }
  final counted = latest.values.toList();
  if (counted.length < rules.minReporters) {
    return CrowdVerdict.no('${counted.length} people nearby, need ${rules.minReporters}');
  }
  final cells = {for (final r in counted) '${r.cellLat},${r.cellLon}'};
  if (cells.length < rules.minCells) return CrowdVerdict.no('all from one place');
  final newest = counted.map((r) => r.at).reduce((a, b) => a.isAfter(b) ? a : b);
  if (u.difference(newest) > rules.freshest) return CrowdVerdict.no('no recent reports');
  var nearest = counted.first;
  var nearestKm = double.infinity;
  for (final r in counted) {
    final d = distanceKm(latDeg, lonDeg, r.cellLat, r.cellLon);
    if (d < nearestKm) {
      nearestKm = d;
      nearest = r;
    }
  }
  return CrowdVerdict._(
    confirmed: true,
    reason: 'go',
    people: counted.length,
    byEye: counted.where((r) => r.how == SeenHow.eye).length,
    nearestKm: nearestKm,
    towardDeg: nearestKm < 1 ? 0 : bearingDeg(latDeg, lonDeg, nearest.cellLat, nearest.cellLon),
  );
}

/// Reports worth asking the relay for: the cells within [radiusKm] of you.
List<({double lat, double lon})> cellsNear(double latDeg, double lonDeg, {double radiusKm = 250}) {
  final dLat = radiusKm / 111.2;
  final dLon = radiusKm / (111.2 * math.max(0.05, math.cos(latDeg * math.pi / 180)));
  final out = <({double lat, double lon})>{};
  for (var la = latDeg - dLat; la <= latDeg + dLat + reportCellDeg; la += reportCellDeg) {
    for (var lo = lonDeg - dLon; lo <= lonDeg + dLon + reportCellDeg; lo += reportCellDeg) {
      final c = reportCell(la, lo);
      if (distanceKm(latDeg, lonDeg, c.lat, c.lon) <= radiusKm + 40) out.add(c);
    }
  }
  return out.toList();
}
