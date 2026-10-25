/// The space station crossing the face of the Sun or the Moon.
///
/// A transit lasts under a second and is only visible from a strip of ground
/// a few kilometres wide, so the useful answer is often "drive 12 km
/// north-west". From the user's spot we find each pass's closest approach to
/// the disk, then walk the observer across the ground until the station's
/// silhouette sits on the disk's centre: moving the observer by D shifts the
/// station's apparent direction by −D⊥/range, while the Sun and Moon barely
/// move. A few iterations with the full SGP4 geometry pin the centre line.
///
/// Photographer territory: these are listed, never pushed.
library;

import 'dart:math' as math;

import 'package:satellite_observer/satellite_observer.dart';

import '../orbit/omm.dart';
import '../sky/astro.dart';

enum TransitBody { sun, moon }

extension TransitBodyInfo on TransitBody {
  String get label => this == TransitBody.sun ? 'Sun' : 'Moon';
}

class Transit {
  const Transit({
    required this.body,
    required this.time,
    required this.separationHereDeg,
    required this.radiusDeg,
    required this.rangeKm,
    required this.bodyAzimuthDeg,
    required this.bodyAltitudeDeg,
    required this.crossing,
    required this.travelKm,
    required this.travelBearingDeg,
    required this.siteLat,
    required this.siteLon,
    required this.halfWidthKm,
  });

  final TransitBody body;

  /// Mid-transit at the recommended site.
  final DateTime time;

  /// Closest approach seen from the user's own spot.
  final double separationHereDeg;
  final double radiusDeg;
  final double rangeKm;
  final double bodyAzimuthDeg;
  final double bodyAltitudeDeg;

  /// How long the silhouette is on the disk at the centre line.
  final Duration crossing;

  /// From the user to the nearest point on the centre line (0 when the user
  /// is already well inside the path).
  final double travelKm;
  final double travelBearingDeg;
  final double siteLat;
  final double siteLon;

  /// Half the width of the strip where the station touches the disk.
  final double halfWidthKm;

  bool get visibleHere => separationHereDeg < radiusDeg;
}

class TransitFinder {
  TransitFinder({
    required this.record,
    this.maxTravelKm = 50,
    this.minBodyAltitudeDeg = 8,
  }) : _elements = record.toElements();

  final OmmRecord record;
  final double maxTravelKm;
  final double minBodyAltitudeDeg;
  final GpElements _elements;

  static const _kmPerDegLat = 111.32;
  static const _coarseStep = Duration(seconds: 2);

  List<Transit> find({
    required double latDeg,
    required double lonDeg,
    required DateTime from,
    required DateTime to,
    Set<TransitBody> bodies = const {TransitBody.sun, TransitBody.moon},
  }) {
    final sat = _observerAt(latDeg, lonDeg);
    final out = <Transit>[];
    for (final pass in sat.passes(from: from.toUtc(), to: to.toUtc(), minElevationDeg: minBodyAltitudeDeg)) {
      for (final body in bodies) {
        final peakBody = _body(body, pass.culmination.utc, latDeg, lonDeg);
        // The body moves ~2° during a pass; skip passes it can't be part of.
        if (peakBody.altitudeDeg < minBodyAltitudeDeg - 3) continue;
        final t = _transitFor(body, pass, sat, latDeg, lonDeg);
        if (t != null) out.add(t);
      }
    }
    out.sort((a, b) => a.time.compareTo(b.time));
    return out;
  }

  SatelliteObserver _observerAt(double lat, double lon) => SatelliteObserver(
      elements: _elements, observer: Observer(latitudeDeg: lat, longitudeDeg: lon));

  static Horizontal _body(TransitBody b, DateTime t, double lat, double lon) =>
      b == TransitBody.sun ? sunHorizontal(t, lat, lon) : moonHorizontal(t, lat, lon);

  static double _radius(TransitBody b, DateTime t, double alt) =>
      b == TransitBody.sun ? sunRadiusDeg(t) : moonRadiusDeg(t, alt);

  /// Separation (deg) of station and body from one observer at [t].
  static double _sep(SatelliteObserver sat, TransitBody b, DateTime t, double lat, double lon) {
    final look = sat.lookAngleAt(t);
    final h = _body(b, t, lat, lon);
    return separationDeg(Horizontal(look.azimuthDeg, look.elevationDeg), h);
  }

  /// Golden-section search for the closest approach in [a, b].
  static DateTime _refine(double Function(DateTime) f, DateTime a, DateTime b) {
    const g = 0.6180339887;
    var lo = a.microsecondsSinceEpoch.toDouble(), hi = b.microsecondsSinceEpoch.toDouble();
    DateTime at(double us) => DateTime.fromMicrosecondsSinceEpoch(us.round(), isUtc: true);
    var x1 = hi - g * (hi - lo), x2 = lo + g * (hi - lo);
    var f1 = f(at(x1)), f2 = f(at(x2));
    while (hi - lo > 2000) {
      if (f1 < f2) {
        hi = x2;
        x2 = x1;
        f2 = f1;
        x1 = hi - g * (hi - lo);
        f1 = f(at(x1));
      } else {
        lo = x1;
        x1 = x2;
        f1 = f2;
        x2 = lo + g * (hi - lo);
        f2 = f(at(x2));
      }
    }
    return at((lo + hi) / 2);
  }

  Transit? _transitFor(TransitBody body, Pass pass, SatelliteObserver sat, double lat, double lon) {
    // Coarse scan of this pass for the closest approach.
    var best = double.infinity;
    DateTime? bestT;
    double bestRange = 0;
    for (var t = pass.rise.utc; !t.isAfter(pass.set.utc); t = t.add(_coarseStep)) {
      final h = _body(body, t, lat, lon);
      if (h.altitudeDeg < minBodyAltitudeDeg) continue;
      final look = sat.lookAngleAt(t);
      final s = separationDeg(Horizontal(look.azimuthDeg, look.elevationDeg), h);
      if (s < best) {
        best = s;
        bestT = t;
        bestRange = look.rangeKm;
      }
    }
    if (bestT == null) return null;
    // Between 2 s samples the station moves at most ~2.2° across the sky.
    final reachDeg = maxTravelKm / bestRange * 180 / math.pi;
    if (best - 1.2 > reachDeg + 0.3) return null;

    var t = _refine((x) => _sep(sat, body, x, lat, lon), bestT.subtract(_coarseStep), bestT.add(_coarseStep));
    final sepHere = _sep(sat, body, t, lat, lon);

    // Walk the observer onto the centre line.
    var siteLat = lat, siteLon = lon;
    var site = sat;
    _Offset? step;
    for (var i = 0; i < 5; i++) {
      step = _offsetToCentre(site, body, t, siteLat, siteLon);
      if (step == null) return null;
      if (step.km < 0.02) break;
      siteLat += step.northKm / _kmPerDegLat;
      siteLon += step.eastKm / (_kmPerDegLat * math.cos(siteLat * math.pi / 180));
      site = _observerAt(siteLat, siteLon);
      final around = t;
      t = _refine((x) => _sep(site, body, x, siteLat, siteLon),
          around.subtract(const Duration(seconds: 20)), around.add(const Duration(seconds: 20)));
      final travel = _distanceKm(lat, lon, siteLat, siteLon);
      if (travel > maxTravelKm * 1.5) return null;
    }
    if (step == null) return null;

    final look = site.lookAngleAt(t);
    final h = _body(body, t, siteLat, siteLon);
    final radius = _radius(body, t, h.altitudeDeg);
    final sepSite = separationDeg(Horizontal(look.azimuthDeg, look.elevationDeg), h);
    if (sepSite > radius * 0.5 || h.altitudeDeg < minBodyAltitudeDeg) return null;

    final travel = _distanceKm(lat, lon, siteLat, siteLon);
    final here = sepHere < radius;
    final halfWidth = radius / step.sensitivityDegPerKm;
    // Already inside the path, comfortably: no need to move.
    final stay = here && travel < halfWidth * 0.6;
    if (!stay && travel > maxTravelKm) return null;

    // Crossing time from the station's speed relative to the disk.
    final dt = const Duration(milliseconds: 250);
    final a = site.lookAngleAt(t.subtract(dt)), b = site.lookAngleAt(t.add(dt));
    final moved = separationDeg(Horizontal(a.azimuthDeg, a.elevationDeg), Horizontal(b.azimuthDeg, b.elevationDeg));
    final degPerSec = moved / (2 * dt.inMilliseconds / 1000);
    final crossingSec = degPerSec <= 0 ? 0.0 : 2 * radius / degPerSec;

    return Transit(
      body: body,
      time: stay ? _refine((x) => _sep(sat, body, x, lat, lon), t.subtract(const Duration(seconds: 20)), t.add(const Duration(seconds: 20))) : t,
      separationHereDeg: sepHere,
      radiusDeg: radius,
      rangeKm: look.rangeKm,
      bodyAzimuthDeg: h.azimuthDeg,
      bodyAltitudeDeg: h.altitudeDeg,
      crossing: Duration(milliseconds: (crossingSec * 1000).round()),
      travelKm: stay ? 0 : travel,
      travelBearingDeg: stay ? 0 : _bearingDeg(lat, lon, siteLat, siteLon),
      siteLat: stay ? lat : siteLat,
      siteLon: stay ? lon : siteLon,
      halfWidthKm: halfWidth,
    );
  }

  /// Ground move (km east/north) that puts the station on the body's centre
  /// at [t], to first order, plus how fast the separation changes per km.
  static _Offset? _offsetToCentre(SatelliteObserver sat, TransitBody body, DateTime t, double lat, double lon) {
    final look = sat.lookAngleAt(t);
    final h = _body(body, t, lat, lon);
    final l = _enu(look.azimuthDeg, look.elevationDeg);
    final m = _enu(h.azimuthDeg, h.altitudeDeg);
    final d = [l[0] - m[0], l[1] - m[1], l[2] - m[2]];
    final sepRad = math.sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]);
    if (sepRad < 1e-9) return const _Offset(0, 0, 1);
    final ue = d[0] / sepRad, un = d[1] / sepRad;
    final uh = math.sqrt(ue * ue + un * un);
    if (uh < 1e-3) return null; // only a vertical move would help
    // Moving D along u shifts the station by −(D·u)/range towards the body.
    final km = sepRad * look.rangeKm / uh;
    final sensitivity = uh / look.rangeKm * 180 / math.pi; // deg per km
    return _Offset(km * ue / uh, km * un / uh, sensitivity);
  }

  static List<double> _enu(double azDeg, double elDeg) {
    final az = azDeg * math.pi / 180, el = elDeg * math.pi / 180;
    return [math.cos(el) * math.sin(az), math.cos(el) * math.cos(az), math.sin(el)];
  }

  static double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    final dn = (lat2 - lat1) * _kmPerDegLat;
    final de = (lon2 - lon1) * _kmPerDegLat * math.cos((lat1 + lat2) / 2 * math.pi / 180);
    return math.sqrt(dn * dn + de * de);
  }

  static double _bearingDeg(double lat1, double lon1, double lat2, double lon2) {
    final dn = (lat2 - lat1) * _kmPerDegLat;
    final de = (lon2 - lon1) * _kmPerDegLat * math.cos((lat1 + lat2) / 2 * math.pi / 180);
    return (math.atan2(de, dn) * 180 / math.pi + 360) % 360;
  }
}

class _Offset {
  const _Offset(this.eastKm, this.northKm, this.sensitivityDegPerKm);
  final double eastKm, northKm, sensitivityDegPerKm;
  double get km => math.sqrt(eastKm * eastKm + northKm * northKm);
}
