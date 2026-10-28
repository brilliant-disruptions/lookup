/// One night at one place: when it's dark, the Moon, the clouds if the
/// forecast reaches that far, and what's worth finding. Tonight is just the
/// coming night's plan; "Plan a night" and favourites look further ahead.
library;

import '../sky/astro.dart';
import '../sky/catalog.dart';
import '../sky/tonight.dart';
import '../sky/visibility.dart';
import '../weather/cloud_forecast.dart';

class NightPlan {
  const NightPlan({
    required this.window,
    required this.outlook,
    required this.planets,
    required this.moon,
    required this.constellations,
    required this.showpieces,
    required this.darkness,
  });

  /// Dark enough to look (sun ≤ −6°); null in polar summer.
  final ({DateTime start, DateTime end})? window;

  /// Clouds through the dark hours; null without a window. Its
  /// `hasForecast` is false when the forecast doesn't reach this night.
  final NightOutlook? outlook;
  final List<PlanetTonight> planets;
  final MoonTonight moon;
  final List<ConstellationTonight> constellations;
  final List<ShowpieceTonight> showpieces;
  final SkyDarkness darkness;

  List<PlanetTonight> get visiblePlanets => [for (final p in planets) if (p.visible) p];

  /// Every sky thing's sighting this night, by [SkyId].
  Map<String, SkySighting?> get sightings => {
        for (final p in planets) SkyId.planet(p.planet): p.whyNot == null ? p.sighting : null,
        SkyId.moon: moon.sighting,
        for (final c in constellations) SkyId.constellation(c.constellation.id): c.sighting,
        for (final s in showpieces) s.showpiece.id: s.sighting,
      };
}

/// The night that follows [at] (tonight if it's daytime or evening, the
/// rest of this night if it's after dark) at [lat]/[lon].
NightPlan planNight({
  required SkyCatalog catalog,
  required DateTime at,
  required double lat,
  required double lon,
  required SkyDarkness darkness,
  CloudForecast? weather,
}) {
  final now = at.toUtc();
  final window = tonightWindow(now, lat, lon);
  return NightPlan(
    window: window,
    outlook: window == null ? null : NightOutlook.from(start: window.start, end: window.end, weather: weather),
    planets: planetsTonight(now: now, lat: lat, lon: lon, darkness: darkness, weather: weather),
    moon: moonTonight(now: now, lat: lat, lon: lon, weather: weather),
    constellations: constellationsTonight(catalog: catalog, now: now, lat: lat, lon: lon, darkness: darkness, weather: weather),
    showpieces: showpiecesTonight(now: now, lat: lat, lon: lon, darkness: darkness, weather: weather),
    darkness: darkness,
  );
}

/// Stable ids for things in the sky, shared by favourites and the Sky tab.
abstract final class SkyId {
  static const moon = 'moon';
  static String planet(Planet p) => 'planet:${p.name}';
  static String constellation(String iauId) => 'con:$iauId';
}

/// A favourite's next good night among [nights] (in order, tonight first):
/// the first one where it's easy to see, with its sighting. Null if none.
({int night, SkySighting sighting})? firstGoodNight(String id, List<NightPlan> nights) {
  for (final (i, n) in nights.indexed) {
    final s = n.sightings[id];
    if (s != null && (s.verdict == Seeability.great || s.verdict == Seeability.good)) return (night: i, sighting: s);
  }
  return null;
}
