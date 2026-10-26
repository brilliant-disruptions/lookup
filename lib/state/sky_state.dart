/// The whole sky tonight: catalog, weather and the per-object verdicts the
/// Sky tab and the Tonight card show. All computed on the phone.
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/sky/catalog.dart';
import '../domain/sky/tonight.dart';
import '../domain/sky/visibility.dart';
import '../domain/weather/cloud_forecast.dart';
import 'providers.dart';

/// Stars and constellations, from the bundled assets (~80 KB).
final skyCatalogProvider = FutureProvider<SkyCatalog>((ref) async {
  final stars = jsonDecode(await rootBundle.loadString('assets/sky/stars.json')) as Map<String, Object?>;
  final cons = jsonDecode(await rootBundle.loadString('assets/sky/constellations.json')) as Map<String, Object?>;
  return SkyCatalog.fromJson(stars, cons);
});

/// The cached hourly forecast; reloaded after every refresh.
final weatherProvider = FutureProvider<CloudForecast?>((ref) async {
  ref.watch(homeProvider); // a refresh may have saved a new forecast
  return ref.read(storeProvider).loadClouds();
});

class TonightSky {
  const TonightSky({
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
  final NightOutlook? outlook;
  final List<PlanetTonight> planets;
  final MoonTonight moon;
  final List<ConstellationTonight> constellations;
  final List<ShowpieceTonight> showpieces;
  final SkyDarkness darkness;

  List<PlanetTonight> get visiblePlanets => [for (final p in planets) if (p.visible) p];
}

/// Recomputed when the place, sky darkness or forecast changes, and at
/// most every 15 minutes otherwise.
final tonightSkyProvider = FutureProvider<TonightSky?>((ref) async {
  final s = await ref.watch(settingsProvider.future);
  if (!s.hasLocation) return null;
  final catalog = await ref.watch(skyCatalogProvider.future);
  final weather = await ref.watch(weatherProvider.future);
  final now = DateTime.now().toUtc();
  final lat = s.latitude!, lon = s.longitude!;
  final window = tonightWindow(now, lat, lon);
  return TonightSky(
    window: window,
    outlook: window == null ? null : NightOutlook.from(start: window.start, end: window.end, weather: weather),
    planets: planetsTonight(now: now, lat: lat, lon: lon, darkness: s.skyDarkness, weather: weather),
    moon: moonTonight(now: now, lat: lat, lon: lon, weather: weather),
    constellations:
        constellationsTonight(catalog: catalog, now: now, lat: lat, lon: lon, darkness: s.skyDarkness, weather: weather),
    showpieces: showpiecesTonight(now: now, lat: lat, lon: lon, darkness: s.skyDarkness, weather: weather),
    darkness: s.skyDarkness,
  );
});

/// Ticks once a minute: the dome map follows the turning sky.
final minuteProvider = StreamProvider<DateTime>(
    (_) => Stream.periodic(const Duration(minutes: 1), (_) => DateTime.now()));
