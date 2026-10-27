/// The whole sky tonight: catalog, weather and the per-object verdicts the
/// Sky tab and the Tonight card show. All computed on the phone.
library;

import 'dart:convert';
import 'dart:io' show gzip;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/plan/night_plan.dart';
import '../domain/sky/catalog.dart';
import '../domain/sky/skyglow.dart';
import '../domain/weather/cloud_forecast.dart';
import 'providers.dart';

/// How bright the night sky is over land, from the bundled night-lights
/// map (~350 KB, see assets/sky/SOURCES-skyglow.txt).
final skyGlowProvider = FutureProvider<SkyGlowMap>((ref) async {
  final data = await rootBundle.load('assets/sky/skyglow.bin.gz');
  final bytes = gzip.decode(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  return SkyGlowMap.decode(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
});

/// Their sky where they are (estimated), and darker places within reach.
/// Null without a location.
final darkSpotsProvider = FutureProvider<({Sqm? here, List<DarkSpot> spots})?>((ref) async {
  final at = await ref.watch(settingsProvider.selectAsync((s) => (lat: s.latitude, lon: s.longitude)));
  if (at.lat == null || at.lon == null) return null;
  final map = await ref.watch(skyGlowProvider.future);
  return (here: map.sqmNear(at.lat!, at.lon!), spots: map.darkerSpots(at.lat!, at.lon!));
});

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

/// Tonight is the coming night's [NightPlan].
typedef TonightSky = NightPlan;

/// Recomputed when the place, sky darkness or forecast changes, and at
/// most every 15 minutes otherwise.
final tonightSkyProvider = FutureProvider<TonightSky?>((ref) async {
  final s = await ref.watch(settingsProvider.future);
  if (!s.hasLocation) return null;
  final catalog = await ref.watch(skyCatalogProvider.future);
  final weather = await ref.watch(weatherProvider.future);
  return planNight(
      catalog: catalog, at: DateTime.now(), lat: s.latitude!, lon: s.longitude!, darkness: s.skyDarkness, weather: weather);
});

/// Ticks once a minute: the dome map follows the turning sky.
final minuteProvider = StreamProvider<DateTime>(
    (_) => Stream.periodic(const Duration(minutes: 1), (_) => DateTime.now()));
