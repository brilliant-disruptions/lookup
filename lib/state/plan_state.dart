/// Looking ahead: the next fortnight of nights here, and when each
/// favourite is next easy to see. Worked out off the UI thread.
library;

import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';

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
