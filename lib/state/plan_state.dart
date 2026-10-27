/// Looking ahead: the next fortnight of nights here, and when each
/// favourite is next easy to see. Worked out off the UI thread.
library;

import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/open_meteo_client.dart';
import '../domain/models/settings.dart';
import '../domain/plan/night_plan.dart';
import '../domain/sky/catalog.dart';
import '../domain/sky/tonight.dart';
import '../domain/sky/visibility.dart';
import '../domain/weather/cloud_forecast.dart';
import 'providers.dart';
import 'sky_state.dart';

/// How far ahead favourites and "Plan a night" look.
const nightsAhead = 14;

List<NightPlan> _plan(
        ({SkyCatalog catalog, DateTime at, double lat, double lon, SkyDarkness darkness, CloudForecast? weather}) a) =>
    [
      for (var i = 0; i < nightsAhead; i++)
        planNight(
            catalog: a.catalog,
            at: a.at.add(Duration(days: i)),
            lat: a.lat,
            lon: a.lon,
            darkness: a.darkness,
            weather: a.weather),
    ];

/// The next [nightsAhead] nights where they are, tonight first. Only the
/// place, their sky and the forecast change it; following something doesn't.
final nightsAheadProvider = FutureProvider<List<NightPlan>?>((ref) async {
  final where = await ref.watch(settingsProvider.selectAsync((s) => (lat: s.latitude, lon: s.longitude, sky: s.skyDarkness)));
  if (where.lat == null || where.lon == null) return null;
  final catalog = await ref.watch(skyCatalogProvider.future);
  final weather = await ref.watch(weatherProvider.future);
  final args = (catalog: catalog, at: DateTime.now().toUtc(), lat: where.lat!, lon: where.lon!, darkness: where.sky, weather: weather);
  return Isolate.run(() => _plan(args));
});

/// A favourite and its next good night ([night] 0 is tonight), or null
/// [sighting] if it isn't well placed in the next fortnight.
typedef FavouriteOutlook = ({String id, int? night, SkySighting? sighting});

final favouritesAheadProvider = FutureProvider<List<FavouriteOutlook>>((ref) async {
  final favourites = await ref.watch(settingsProvider.selectAsync((s) => s.favourites));
  if (favourites.isEmpty) return const [];
  final nights = await ref.watch(nightsAheadProvider.future);
  if (nights == null) return const [];
  return [
    for (final id in favourites)
      if (firstGoodNight(id, nights) case final good?)
        (id: id, night: good.night, sighting: good.sighting)
      else
        (id: id, night: null, sighting: null),
  ];
});

/// Somewhere to look from: where they are now, or a saved place.
typedef Spot = ({String name, double lat, double lon, SkyDarkness? darkness, bool here});

/// Here first, then saved places that aren't here.
List<Spot> planSpots(LookUpSettings s) => [
      if (s.hasLocation)
        (
          name: (s.placeName?.isNotEmpty ?? false) ? s.placeName! : 'Here',
          lat: s.latitude!,
          lon: s.longitude!,
          darkness: s.activePlace?.skyDarkness,
          here: true,
        ),
      for (final p in s.places)
        if (!s.hasLocation || !p.sameSpot(s.latitude!, s.longitude!))
          (name: p.name, lat: p.latitude, lon: p.longitude, darkness: p.skyDarkness, here: false),
    ];

final openMeteoProvider = Provider<OpenMeteoClient>((_) => OpenMeteoClient());

/// Hourly clouds for a place: the main forecast when it's where they are,
/// otherwise the place's own copy, fetched only when looked at and at most
/// every 6 hours (Open-Meteo etiquette, see CLAUDE.md).
final placeForecastProvider = FutureProvider.family<CloudForecast?, ({double lat, double lon})>((ref, at) async {
  final main = await ref.watch(weatherProvider.future);
  if (main != null && (main.latitude - at.lat).abs() < 0.2 && (main.longitude - at.lon).abs() < 0.2) return main;
  final store = ref.read(storeProvider);
  final cached = await store.loadPlaceClouds(at.lat, at.lon);
  if (cached != null && !cached.isStale(DateTime.now(), maxAge: placeCloudsMaxAge)) return cached;
  try {
    final fresh = await ref.read(openMeteoProvider).fetchCloudForecast(at.lat, at.lon, pastDays: 0);
    await store.savePlaceClouds(fresh);
    return fresh;
  } catch (_) {
    return cached;
  }
});

const placeCloudsMaxAge = Duration(hours: 6);

/// One night ([night] 0 = tonight) at one place, with that place's clouds.
final nightPlanProvider =
    FutureProvider.family<NightPlan, ({double lat, double lon, int night, SkyDarkness darkness})>((ref, k) async {
  final catalog = await ref.watch(skyCatalogProvider.future);
  final weather = await ref.watch(placeForecastProvider((lat: k.lat, lon: k.lon)).future);
  return planNight(
      catalog: catalog,
      at: DateTime.now().toUtc().add(Duration(days: k.night)),
      lat: k.lat,
      lon: k.lon,
      darkness: k.darkness,
      weather: weather);
});
