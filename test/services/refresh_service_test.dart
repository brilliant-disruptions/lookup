import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lookup/data/celestrak_client.dart';
import 'package:lookup/data/launch_library_client.dart';
import 'package:lookup/data/local_store.dart';
import 'package:lookup/data/open_meteo_client.dart';
import 'package:lookup/data/swpc_client.dart';
import 'package:lookup/domain/scheduling/alert_planner.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/services/location_service.dart';
import 'package:lookup/services/notification_service.dart';
import 'package:lookup/services/refresh_service.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _Here extends LocationService {
  const _Here();
  @override
  Future<LatLon?> resolve(LookUpSettings s, {bool allowPrompt = false}) async => (lat: 40.0, lon: -75.0);
}

class _Notes implements NotificationService {
  @override
  Future<Set<int>> applyPlan(List<PlannedAlert> plan, Set<int> previous) async => const {};
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Every source behind one network that holds each request until [open]s,
/// so a test can see which were asked for at the same time.
class _Network {
  final asked = <String>[];
  final _gate = Completer<void>();
  void open() => _gate.complete();

  late final client = MockClient((req) async {
    final url = req.url.toString();
    asked.add(url);
    await _gate.future;
    if (url.contains('CATNR=25544')) return http.Response(File('test/fixtures/iss_omm.json').readAsStringSync(), 200);
    if (url.contains('GROUP=starlink')) {
      return http.Response(File('test/fixtures/starlink_sample.json').readAsStringSync(), 200);
    }
    if (url.contains('sup-gp.php')) return http.Response('[]', 200);
    return http.Response('not here', 404); // the rest fail; tolerated
  });

  RefreshService service(LocalStore store) => RefreshService(
        store: store,
        notifications: _Notes(),
        celestrak: CelestrakClient(client: client),
        swpc: SwpcClient(client: client),
        meteo: OpenMeteoClient(client: client),
        launchLibrary: LaunchLibraryClient(client: client),
        location: const _Here(),
        catalog: () async => throw 'no sky in this test',
      );
}

/// Lets the run reach the network, opens it, then waits out the failures' retries.
Future<RefreshReport> _finish(WidgetTester t, _Network net, Future<RefreshReport> run) async {
  await t.pump(const Duration(milliseconds: 100));
  net.open();
  RefreshReport? report;
  unawaited(run.then((r) => report = r));
  for (var i = 0; i < 20 && report == null; i++) {
    await t.pump(const Duration(seconds: 5));
  }
  return report!;
}

void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());

  // One after another, a first refresh waited for the sum of every source
  // (the 4.7 MB Starlink catalogue included); together it waits for the slowest.
  testWidgets('the sources download at the same time', (t) async {
    final net = _Network();
    final store = LocalStore();
    final run = net.service(store).run();
    await t.pump(const Duration(milliseconds: 100));
    // Nothing has answered yet, yet every source has been asked.
    final hosts = {for (final u in net.asked) Uri.parse(u).host};
    expect(hosts, containsAll(['celestrak.org', 'api.open-meteo.com', 'services.swpc.noaa.gov', 'll.thespacedevs.com']));
    expect(net.asked.where((u) => u.contains('CATNR=25544')), hasLength(1));
    expect(net.asked.where((u) => u.contains('GROUP=starlink')), hasLength(1));

    final report = await _finish(t, net, run);
    expect(report.events, isNotEmpty);
    expect(await store.loadLastRefresh(), isNotNull);
  });

  // Onboarding's first look: Starlink can't hold up the first sights.
  testWidgets('a quick refresh skips the Starlink download and leaves the refresh not done', (t) async {
    final net = _Network();
    final store = LocalStore();
    final report = await _finish(t, net, net.service(store).run(quick: true));
    expect(net.asked.where((u) => u.contains('starlink')), isEmpty);
    expect(net.asked.where((u) => u.contains('CATNR=25544')), hasLength(1));
    expect(report.events, isNotEmpty, reason: 'the ISS is enough for a first look');
    expect(await store.loadLastRefresh(), isNull, reason: 'a full refresh must still follow');
  });

  testWidgets('a quick refresh still uses a fresh cached Starlink', (t) async {
    final store = LocalStore();
    final full = _Network();
    await _finish(t, full, full.service(store).run());
    expect(await store.loadElements('starlink'), isNotNull);

    final quick = _Network();
    await _finish(t, quick, quick.service(store).run(quick: true));
    expect(quick.asked.where((u) => u.contains('celestrak')), isEmpty, reason: 'the ISS and Starlink were fresh');
  });

  // Celestrak not answering at all held the first look ~3 minutes (60 s
  // timeout × 3 tries); onboarding must not wait that long for a first look.
  testWidgets('a quick refresh gives up on a source that never answers', (t) async {
    final silent = MockClient((req) => Completer<http.Response>().future);
    final service = RefreshService(
      store: LocalStore(),
      notifications: _Notes(),
      celestrak: CelestrakClient(client: silent),
      swpc: SwpcClient(client: silent),
      meteo: OpenMeteoClient(client: silent),
      launchLibrary: LaunchLibraryClient(client: silent),
      location: const _Here(),
      catalog: () async => throw 'no sky in this test',
    );
    RefreshReport? report;
    unawaited(service.run(quick: true).then((r) => report = r));
    await t.pump(const Duration(seconds: 9));
    expect(report, isNull);
    await t.pump(const Duration(seconds: 2));
    expect(report, isNotNull, reason: 'gone on after RefreshService.quickLimit');
    expect(report!.errors.where((e) => e.startsWith('iss')), isNotEmpty);
    await t.pump(const Duration(minutes: 4)); // let the abandoned requests' own retries run out
  });
}
