import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/data/local_store.dart';
import 'package:lookup/data/open_meteo_client.dart';
import 'package:lookup/domain/weather/cloud_forecast.dart';
import 'package:lookup/state/plan_state.dart';
import 'package:lookup/state/sky_state.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _Meteo extends OpenMeteoClient {
  int calls = 0;
  bool offline = false;

  @override
  Future<CloudForecast> fetchCloudForecast(double lat, double lon, {int days = 7, int pastDays = 7}) async {
    calls++;
    if (offline) throw Exception('offline');
    return CloudForecast(latitude: lat, longitude: lon, fetchedAt: DateTime.now().toUtc(), hourly: const []);
  }
}

void main() {
  final home = CloudForecast(latitude: 36.17, longitude: -86.78, fetchedAt: DateTime.now().toUtc(), hourly: const []);
  const cabin = (lat: 35.61, lon: -83.49);
  late _Meteo meteo;

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [
      weatherProvider.overrideWith((_) async => home),
      openMeteoProvider.overrideWithValue(meteo),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    meteo = _Meteo();
  });

  test('where they are uses the main forecast, no extra fetch', () async {
    final f = await container().read(placeForecastProvider((lat: 36.2, lon: -86.8)).future);
    expect(identical(f, home), isTrue);
    expect(meteo.calls, 0);
  });

  test('another place is fetched once, then served from its cache for 6 hours', () async {
    final first = await container().read(placeForecastProvider(cabin).future);
    expect(first?.latitude, cabin.lat);
    expect(meteo.calls, 1);
    // A later session (fresh container) reads the cache instead of fetching.
    await container().read(placeForecastProvider(cabin).future);
    expect(meteo.calls, 1);
  });

  test('a stale copy is refetched; offline, the stale copy is still used', () async {
    final old = CloudForecast(
        latitude: cabin.lat,
        longitude: cabin.lon,
        fetchedAt: DateTime.now().toUtc().subtract(placeCloudsMaxAge + const Duration(minutes: 1)),
        hourly: const []);
    await LocalStore().savePlaceClouds(old);
    meteo.offline = true;
    final f = await container().read(placeForecastProvider(cabin).future);
    expect(meteo.calls, 1);
    expect(f?.fetchedAt, old.fetchedAt);
  });

  test('nearby spots share a cached copy', () {
    expect(LocalStore.placeCloudsKey(35.61, -83.49), LocalStore.placeCloudsKey(35.63, -83.51));
    expect(LocalStore.placeCloudsKey(35.61, -83.49), isNot(LocalStore.placeCloudsKey(35.81, -83.49)));
  });
}
