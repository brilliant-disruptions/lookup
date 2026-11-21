// What has gone out stays out of the schedule: a refresh never cancels an
// alert that's on the Lock Screen, and never sends one twice.
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lookup/data/celestrak_client.dart';
import 'package:lookup/data/launch_library_client.dart';
import 'package:lookup/data/local_store.dart';
import 'package:lookup/data/open_meteo_client.dart';
import 'package:lookup/data/swpc_client.dart';
import 'package:lookup/domain/aurora/aurora_rules.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/scheduling/alert_planner.dart';
import 'package:lookup/domain/sky/sun.dart';
import 'package:lookup/services/notification_service.dart';
import 'package:lookup/services/refresh_service.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// Writes down what the notification plugin was asked to do.
class _Plugin implements FlutterLocalNotificationsPlugin {
  final shown = <int>[];
  final cancelled = <int>[];
  @override
  dynamic noSuchMethod(Invocation i) {
    final id = i.namedArguments[#id];
    if (i.memberName == #show && id is int) shown.add(id);
    if (i.memberName == #cancel && id is int) cancelled.add(id);
    return Future<void>.value();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());

  test('"Aurora now" goes out once in its three hours, however often the app refreshes', () async {
    await HttpOverrides.runZoned(() async {
      final now = DateTime.now().toUtc();
      // Wherever it's the middle of the night at 50° north right now: dark in any season.
      var lon = -180.0;
      for (var l = -180.0; l < 180; l += 5) {
        if (sunAltitudeDeg(now, 50, l) < sunAltitudeDeg(now, 50, lon)) lon = l;
      }
      expect(isDark(now, 50, lon, thresholdDeg: auroraDarkDeg), isTrue);
      final gridLon = ((lon.round() % 360) + 360) % 360;
      final client = MockClient((req) async {
        final u = req.url.toString();
        if (u.contains('CATNR=25544')) return http.Response(File('test/fixtures/iss_omm.json').readAsStringSync(), 200);
        if (u.contains('open-meteo')) return http.Response('{"hourly":{"time":[],"cloud_cover":[]}}', 200);
        if (u.contains('planetary_k_index_1m')) return http.Response('[{"estimated_kp": 9}]', 200);
        if (u.contains('k-index-forecast')) return http.Response('[]', 200);
        if (u.contains('ovation')) return http.Response('{"coordinates": [[$gridLon, 50, 90]]}', 200);
        return http.Response('[]', 200);
      });
      final store = LocalStore();
      await store.saveSettings(LookUpSettings(
        latitude: 50,
        longitude: lon,
        locationMode: LocationMode.pinned,
        isPlus: true,
        onboarded: true,
        starlinkEnabled: false,
        launchesEnabled: false,
        weekAhead: false,
        quietHours: const QuietHours(startMinute: 0, endMinute: 0),
      ));
      final plugin = _Plugin();
      final svc = RefreshService(
        store: store,
        notifications: NotificationService(plugin, (_) async => null),
        celestrak: CelestrakClient(client: client),
        swpc: SwpcClient(client: client),
        meteo: OpenMeteoClient(client: client),
        launchLibrary: LaunchLibraryClient(client: client),
        catalog: () async => throw 'none',
        issSeed: () async => const [],
      );
      int? id;
      for (var i = 0; i < 3; i++) {
        final r = await svc.run();
        final aurora = r.events.where((e) => e.type == SkyEventType.auroraNow).toList();
        expect(aurora, hasLength(1), reason: 'refresh ${i + 1}: ${r.errors}');
        id ??= AlertPlanner.notificationIdFor(aurora.single.id, AlertKind.headsUp);
        // A bucket can turn over mid-test (every three hours): then it's a new aurora.
        if (AlertPlanner.notificationIdFor(aurora.single.id, AlertKind.headsUp) != id) return;
      }
      expect(plugin.shown.where((s) => s == id), hasLength(1), reason: 'shown once, not at every refresh');
      expect(plugin.cancelled, isNot(contains(id)), reason: 'never taken off the Lock Screen by a refresh');
    }, createHttpClient: (_) => throw 'no real network');
  });
}
