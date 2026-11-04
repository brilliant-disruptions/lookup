/// Where a saved place is, in words people know: "In Nashville",
/// "25 miles east of Knoxville". From the bundled towns of 50,000+
/// (assets/sky/places.json), so it works offline and asks no server.
library;

import '../satellites/under_the_pass.dart' show Place;
import '../sky/direction.dart';
import '../units.dart';
import 'where_to_go.dart' show bearingDeg, distanceKm;

/// Within this of a town's centre, you're "in" it.
const inTownKm = 10.0;

/// Beyond this, no town is a useful landmark: null.
const landmarkKm = 120.0;

String? nearTown(double lat, double lon, List<Place> towns, {required bool miles}) {
  Place? best;
  var bestKm = double.infinity;
  for (final t in towns) {
    // Cheap box first: a degree of latitude is ~111 km.
    if ((t.lat - lat).abs() > 2) continue;
    final d = distanceKm(lat, lon, t.lat, t.lon);
    if (d < bestKm) {
      bestKm = d;
      best = t;
    }
  }
  if (best == null || bestKm > landmarkKm) return null;
  if (bestKm < inTownKm) return 'In ${best.name}';
  return '${distanceWords(bestKm, miles: miles)} ${compassWord(bearingDeg(best.lat, best.lon, lat, lon))} of ${best.name}';
}
