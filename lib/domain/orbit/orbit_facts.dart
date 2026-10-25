/// Small, true facts about a satellite at a moment: speed, height, laps.
library;

import 'dart:math' as math;

import 'package:satellite_observer/satellite_observer.dart';

import 'omm.dart';

class OrbitFacts {
  const OrbitFacts({required this.speedKmS, required this.altitudeKm, required this.orbitsPerDay, required this.minutesPerOrbit});
  final double speedKmS;
  final double altitudeKm;
  final double orbitsPerDay;
  final double minutesPerOrbit;

  double get speedMph => speedKmS * 2236.936;

  static OrbitFacts at(OmmRecord r, DateTime utc) {
    final sat = SatelliteObserver(elements: r.toElements(), observer: Observer(latitudeDeg: 0, longitudeDeg: 0));
    final v = sat.propagate(utc.toUtc()).velocity;
    final sub = sat.subPointAt(utc.toUtc());
    return OrbitFacts(
      speedKmS: math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z),
      altitudeKm: sub.altitudeKm,
      orbitsPerDay: r.meanMotion,
      minutesPerOrbit: 1440 / r.meanMotion,
    );
  }
}
