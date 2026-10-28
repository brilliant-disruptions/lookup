/// How bright the night sky is anywhere on land, from satellite night
/// lights (see assets/sky/SOURCES-skyglow.txt), and darker spots nearby.
/// An estimate: a map of light, not of roads or of what's open at night.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../plan/where_to_go.dart' show bearingDeg, distanceKm;
import 'visibility.dart';

/// Zenith sky brightness in mag/arcsec², the number a Sky Quality Meter
/// reads: about 22 for a natural sky, 18 under a city.
typedef Sqm = double;

/// At or above this, the Milky Way shows: a [SkyDarkness.dark] sky. Set
/// on the strict side: the map runs ~0.4 mag optimistic just outside towns.
const Sqm darkSkySqm = 21.2;

/// Below this, only the brightest stars: a [SkyDarkness.city] sky. The
/// source image saturates over whole metro areas, so inner suburbs read
/// about as bright as downtown; this keeps them "suburbs".
const Sqm citySkySqm = 18.3;

SkyDarkness darknessForSqm(Sqm m) => m >= darkSkySqm
    ? SkyDarkness.dark
    : m < citySkySqm
        ? SkyDarkness.city
        : SkyDarkness.suburbs;

/// A spot worth driving to for a darker sky.
typedef DarkSpot = ({double lat, double lon, Sqm sqm, double distanceKm, double bearingDeg});

class SkyGlowMap {
  SkyGlowMap({
    required this.north,
    required this.west,
    required this.step,
    required this.rows,
    required this.cols,
    required this.cells,
  }) : assert(cells.length == rows * cols);

  /// Reads the (already gunzipped) asset; see tool/skyglow/build_skyglow.py.
  factory SkyGlowMap.decode(Uint8List bytes) {
    final h = ByteData.sublistView(bytes);
    if (String.fromCharCodes(bytes.sublist(0, 4)) != 'LUSG' || bytes[4] != 1) {
      throw const FormatException('Not a v1 sky glow map');
    }
    final rows = h.getUint32(20, Endian.little), cols = h.getUint32(24, Endian.little);
    return SkyGlowMap(
      north: h.getFloat32(8, Endian.little),
      west: h.getFloat32(12, Endian.little),
      step: h.getFloat32(16, Endian.little),
      rows: rows,
      cols: cols,
      cells: Uint8List.sublistView(bytes, 28, 28 + rows * cols),
    );
  }

  final double north, west, step;
  final int rows, cols;

  /// 0 for water or no data, else 16 + (b − 1) × 0.025 mag/arcsec².
  final Uint8List cells;

  int? _row(double lat) {
    final r = ((north - lat) / step).floor();
    return r < 0 || r >= rows ? null : r;
  }

  int _col(double lon) => (((lon - west) / step).floor()) % cols;

  Sqm? _at(int r, int c) {
    final b = cells[r * cols + c % cols];
    return b == 0 ? null : 16 + (b - 1) * 0.025;
  }

  /// The sky's brightness at a place; null over water or off the map.
  Sqm? sqmAt(double lat, double lon) {
    final r = _row(lat);
    return r == null ? null : _at(r, _col(lon));
  }

  /// [sqmAt], or the nearest land within a cell or two (a lakefront city's
  /// own cell can be water).
  Sqm? sqmNear(double lat, double lon) {
    final m = sqmAt(lat, lon);
    if (m != null) return m;
    final r0 = _row(lat);
    if (r0 == null) return null;
    final c0 = _col(lon);
    for (var ring = 1; ring <= 2; ring++) {
      Sqm? best;
      for (var r = r0 - ring; r <= r0 + ring; r++) {
        if (r < 0 || r >= rows) continue;
        for (var c = c0 - ring; c <= c0 + ring; c++) {
          final x = _at(r, c % cols);
          // The brightest neighbour: never make a city look darker than it is.
          if (x != null && (best == null || x < best)) best = x;
        }
      }
      if (best != null) return best;
    }
    return null;
  }

  /// Up to [max] places within [radiusKm] where the sky is clearly darker
  /// than at [lat]/[lon], nearest first, at least [spacingKm] apart. The
  /// nearest properly dark sky comes first if there is one; then the best
  /// trade of darkness against distance.
  List<DarkSpot> darkerSpots(double lat, double lon,
      {double radiusKm = 150, int max = 3, double spacingKm = 40}) {
    final here = sqmNear(lat, lon) ?? 0;
    // Clearly darker, and dark enough to be worth a drive.
    final floor = here + 0.5 > 20.0 ? here + 0.5 : 20.0;
    final r0 = _row(lat);
    if (r0 == null) return const [];
    final dr = (radiusKm / (step * 110.57)).ceil();
    final candidates = <DarkSpot>[];
    for (var r = r0 - dr; r <= r0 + dr; r++) {
      if (r < 0 || r >= rows) continue;
      final cLat = north - (r + 0.5) * step;
      final kmPerCol = step * 111.32 * _cos(cLat);
      final dc = kmPerCol < 1 ? cols ~/ 2 : (radiusKm / kmPerCol).ceil();
      final c0 = _col(lon);
      for (var c = c0 - dc; c <= c0 + dc; c++) {
        final m = _at(r, c % cols);
        if (m == null || m < floor) continue;
        final cLon = west + (c + 0.5) * step;
        final d = distanceKm(lat, lon, cLat, cLon);
        if (d > radiusKm) continue;
        candidates.add((lat: cLat, lon: _wrap(cLon), sqm: m, distanceKm: d, bearingDeg: bearingDeg(lat, lon, cLat, cLon)));
      }
    }
    if (candidates.isEmpty) return const [];
    final picked = <DarkSpot>[];
    bool farFromPicked(DarkSpot s) => picked.every((p) => distanceKm(p.lat, p.lon, s.lat, s.lon) >= spacingKm);

    final dark = candidates.where((s) => s.sqm >= darkSkySqm).toList()
      ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    if (dark.isNotEmpty) picked.add(dark.first);
    // One magnitude of darkness is worth about 100 km of driving.
    double score(DarkSpot s) => s.sqm - s.distanceKm / 100;
    final ranked = candidates.toList()..sort((a, b) => score(b).compareTo(score(a)));
    for (final s in ranked) {
      if (picked.length >= max) break;
      if (farFromPicked(s)) picked.add(s);
    }
    return picked..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
  }

  static double _wrap(double lon) => lon > 180 ? lon - 360 : lon < -180 ? lon + 360 : lon;
  static double _cos(double deg) => math.cos(deg * math.pi / 180);
}
