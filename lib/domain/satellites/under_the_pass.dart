/// "Who else was under it": roughly how many people had the same pass in a
/// dark sky at the same moments you did. Every town of 50,000+ that, at some
/// moment of your visible pass, had the satellite at least 10° up and the
/// Sun at least 6° down. Clouds aren't counted, so it's who was *under* it,
/// never who saw it. Pure.
library;

import 'dart:math' as math;

import 'package:satellite_observer/satellite_observer.dart';

import '../models/sky_event.dart';
import '../orbit/omm.dart';
import '../sky/sun.dart';

class Place {
  const Place(this.name, this.lat, this.lon, this.people);
  final String name;
  final double lat;
  final double lon;
  final int people;

  /// Rows of assets/sky/places.json: [name, lat, lon, thousands].
  static List<Place> fromJson(List<Object?> rows) => [
    for (final r in rows.cast<List<Object?>>())
      Place(r[0]! as String, (r[1]! as num).toDouble(), (r[2]! as num).toDouble(), (r[3]! as num).toInt() * 1000),
  ];
}

/// A moment of the pass: where the satellite is over the ground.
typedef TrackPoint = ({DateTime t, double lat, double lon, double altKm});

class UnderThePass {
  const UnderThePass({required this.people, required this.places, required this.biggest});

  /// People in the towns under it (not counting where you are).
  final int people;
  final int places;

  /// The biggest of them, largest first, at most three.
  final List<String> biggest;

  /// "3.4 million", "870,000": two significant figures, in words people say.
  String get peopleWords => roundedPeople(people);

  /// "Atlanta, Louisville and 38 other places".
  String get placesWords {
    final others = places - biggest.length;
    final parts = [...biggest, if (others > 0) '$others other ${others == 1 ? 'place' : 'places'}'];
    return parts.length <= 1 ? parts.join() : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  }

  static const _earthKm = 6371.0;
  static const _deg = math.pi / 180;

  /// Ground distance (central angle, degrees) within which a satellite at
  /// [altKm] stands at least [minElevationDeg] above the horizon.
  static double footprintDeg(double altKm, {double minElevationDeg = 10}) {
    final e = minElevationDeg * _deg;
    return (math.acos(_earthKm * math.cos(e) / (_earthKm + altKm)) - e) / _deg;
  }

  static double _centralDeg(double lat1, double lon1, double lat2, double lon2) {
    final p1 = lat1 * _deg, p2 = lat2 * _deg, dl = (lon2 - lon1) * _deg;
    final h = math.pow(math.sin((p2 - p1) / 2), 2) + math.cos(p1) * math.cos(p2) * math.pow(math.sin(dl / 2), 2);
    return 2 * math.asin(math.min(1.0, math.sqrt(h))) / _deg;
  }

  /// Who was under [track] (your visible pass) in a dark sky. Places within
  /// [hereKm] of you are left out: you're counted separately, as "you".
  /// Null if the track is empty or nobody else was under it.
  static UnderThePass? estimate({
    required List<TrackPoint> track,
    required List<Place> places,
    required double hereLat,
    required double hereLon,
    double hereKm = 40,
  }) {
    if (track.isEmpty) return null;
    final reach = [for (final p in track) footprintDeg(p.altKm)];
    final maxReach = reach.reduce(math.max);
    final minLat = track.map((p) => p.lat).reduce(math.min) - maxReach;
    final maxLat = track.map((p) => p.lat).reduce(math.max) + maxReach;
    final under = <Place>[];
    for (final place in places) {
      if (place.lat < minLat || place.lat > maxLat) continue;
      if (_centralDeg(place.lat, place.lon, hereLat, hereLon) * _deg * _earthKm < hereKm) continue;
      for (var i = 0; i < track.length; i++) {
        final p = track[i];
        if (_centralDeg(place.lat, place.lon, p.lat, p.lon) > reach[i]) continue;
        if (sunAltitudeDeg(p.t, place.lat, place.lon) <= -6) {
          under.add(place);
          break;
        }
      }
    }
    if (under.isEmpty) return null;
    under.sort((a, b) => b.people.compareTo(a.people));
    return UnderThePass(
      people: under.fold(0, (s, p) => s + p.people),
      places: under.length,
      biggest: [for (final p in under.take(3)) p.name],
    );
  }

  /// The ground track of [e] from start to end, every [step], from the
  /// elements it carries. Empty when it has none.
  static List<TrackPoint> trackOf(SkyEvent e, {Duration step = const Duration(seconds: 15)}) {
    final omm = e.details['omm'];
    if (omm is! Map) return const [];
    try {
      final sat = SatelliteObserver(
        elements: OmmRecord.fromJson(omm.cast<String, Object?>()).toElements(),
        observer: Observer(latitudeDeg: 0, longitudeDeg: 0),
      );
      return [
        for (var t = e.start; !t.isAfter(e.end); t = t.add(step))
          () {
            final s = sat.subPointAt(t);
            return (t: t, lat: s.latitudeDeg, lon: s.longitudeDeg, altKm: s.altitudeKm);
          }(),
      ];
    } catch (_) {
      return const [];
    }
  }
}

/// Two significant figures: 3,412,000 → "3.4 million", 872,000 → "870,000".
String roundedPeople(int n) {
  if (n <= 0) return '0';
  final digits = n.toString().length;
  final unit = math.pow(10, math.max(0, digits - 2)).toInt();
  final r = (n / unit).round() * unit;
  if (r >= 1000000) {
    final m = r / 1000000;
    final s = m >= 10 ? m.round().toString() : m.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
    return '$s million';
  }
  final s = r.toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}
