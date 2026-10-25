/// Rocket launches visible from the user's location.
///
/// Heuristic: launches are visible to roughly 1,000 km from the pad when the
/// sky is dark or in twilight, when sunlit exhaust plumes ("jellyfish")
/// are spectacular. We stay conservative to avoid false alarms.
library;

import 'dart:math' as math;

import '../models/sky_event.dart';
import '../sky/sun.dart';

class Launch {
  const Launch({required this.id, required this.name, required this.net, required this.padLat, required this.padLon, required this.padName, this.provider, this.status});
  final String id;
  final String name;
  final DateTime net;
  final double padLat, padLon;
  final String padName;
  final String? provider;
  final String? status; // Go, TBD, TBC, Success...

  static Launch? fromLaunchLibrary(Map<String, Object?> j) {
    final pad = j['pad'] as Map?;
    final lat = double.tryParse('${pad?['latitude']}');
    final lon = double.tryParse('${pad?['longitude']}');
    final net = DateTime.tryParse('${j['net']}');
    if (lat == null || lon == null || net == null) return null;
    return Launch(
      id: '${j['id']}',
      name: '${j['name']}',
      net: net.toUtc(),
      padLat: lat,
      padLon: lon,
      padName: '${(pad?['location'] as Map?)?['name'] ?? pad?['name'] ?? ''}',
      provider: (j['launch_service_provider'] as Map?)?['name'] as String?,
      status: (j['status'] as Map?)?['abbrev'] as String?,
    );
  }
}

double distanceKm(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0, k = math.pi / 180;
  final dLat = (lat2 - lat1) * k, dLon = (lon2 - lon1) * k;
  final a = math.pow(math.sin(dLat / 2), 2) + math.cos(lat1 * k) * math.cos(lat2 * k) * math.pow(math.sin(dLon / 2), 2);
  return 2 * r * math.asin(math.sqrt(a.toDouble()));
}

double bearingDeg(double lat1, double lon1, double lat2, double lon2) {
  const k = math.pi / 180;
  final y = math.sin((lon2 - lon1) * k) * math.cos(lat2 * k);
  final x = math.cos(lat1 * k) * math.sin(lat2 * k) - math.sin(lat1 * k) * math.cos(lat2 * k) * math.cos((lon2 - lon1) * k);
  return ((math.atan2(y, x) / k) + 360) % 360;
}

List<SkyEvent> launchEvents({
  required List<Launch> launches,
  required DateTime now,
  required double latDeg,
  required double lonDeg,
  double maxDistanceKm = 1000,
  Duration window = const Duration(days: 7),
}) {
  final out = <SkyEvent>[];
  for (final l in launches) {
    if (l.net.isBefore(now) || l.net.isAfter(now.add(window))) continue;
    if (l.status != null && !{'Go', 'TBC', 'TBD'}.contains(l.status)) continue;
    final dist = distanceKm(latDeg, lonDeg, l.padLat, l.padLon);
    if (dist > maxDistanceKm) continue;
    final sunAlt = sunAltitudeDeg(l.net, latDeg, lonDeg);
    if (sunAlt > -4) continue; // daylight: not worth a tap
    final twilight = sunAlt > -18;
    final az = bearingDeg(latDeg, lonDeg, l.padLat, l.padLon);
    // Rough apparent elevation: rockets climb to ~150 km within minutes.
    final el = dist < 50 ? 45.0 : math.atan2(150, dist) * 180 / math.pi;
    out.add(SkyEvent(
      id: 'launch:${l.id}',
      type: SkyEventType.rocketLaunch,
      start: l.net,
      peak: l.net.add(const Duration(minutes: 2)),
      end: l.net.add(const Duration(minutes: 6)),
      peakElevationDeg: el,
      riseAzimuthDeg: az,
      peakAzimuthDeg: az,
      setAzimuthDeg: az,
      details: {
        'name': l.name,
        'pad': l.padName,
        'provider': l.provider,
        'distanceKm': dist.round(),
        'twilight': twilight,
        'label': twilight ? 'Rocket launch at twilight' : 'Rocket launch',
      },
    ));
  }
  return out;
}
