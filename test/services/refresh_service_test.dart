import 'dart:async';
import 'dart:convert';
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
import 'package:lookup/domain/scheduling/alert_tuning.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/orbit/omm.dart';
import 'package:lookup/services/location_service.dart';
import 'package:lookup/services/notification_service.dart';
import 'package:lookup/services/refresh_service.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _Here extends LocationService {
  _Here();

  /// The `anyAge` of each location asked for.
  final anyAge = <bool>[];
  @override
  Future<LatLon?> resolve(LookUpSettings s, {bool allowPrompt = false, bool anyAge = false}) async {
    this.anyAge.add(anyAge);
    return (lat: 40.0, lon: -75.0);
  }
}

class _Notes implements NotificationService {
  /// The last plan scheduled.
  List<PlannedAlert>? planned;
  @override
  Future<Set<int>> applyPlan(List<PlannedAlert> plan, Set<int> previous) async {
    planned = plan;
    return const {};
  }
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Records what it was asked to plan from: the gates after it (clouds,
/// quiet hours) can hide an ISS pass that should never have reached it.
class _Planner extends AlertPlanner {
  List<SkyEvent>? given;
  @override
  List<PlannedAlert> plan({
    required List<SkyEvent> events,
    required LookUpSettings settings,
    required DateTime now,
    required int utcOffsetMinutes,
    Duration horizon = const Duration(hours: 48),
    AlertTuning tuning = AlertTuning.neutral,
  }) {
    given = events;
    return super.plan(
        events: events, settings: settings, now: now, utcOffsetMinutes: utcOffsetMinutes, horizon: horizon, tuning: tuning);
  }
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
        location: _Here(),
        catalog: () async => throw 'no sky in this test',
        issSeed: () async => const [],
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
    // The aurora's forecast, Kp now and map together, not one after another.
    expect(net.asked.where((u) => u.contains('swpc')), hasLength(3));

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
      location: _Here(),
      catalog: () async => throw 'no sky in this test',
      issSeed: () async => const [],
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

  // The ISS and launches are fetched while the user reads the intro and
  // answers the location prompt; the first look must reuse that download,
  // not ask Celestrak again (once a day per feed).
  testWidgets('a prefetch and the quick look share one ISS download', (t) async {
    final net = _Network();
    final service = net.service(LocalStore());
    final prefetch = service.prefetch();
    await t.pump(const Duration(milliseconds: 100));
    final quick = service.run(quick: true);
    var prefetched = false;
    unawaited(prefetch.then((_) => prefetched = true));
    final report = await _finish(t, net, quick);
    for (var i = 0; i < 20 && !prefetched; i++) {
      await t.pump(const Duration(seconds: 5));
    }
    expect(prefetched, isTrue);
    expect(net.asked.where((u) => u.contains('CATNR=25544')), hasLength(1));
    expect(report.events, isNotEmpty);
  });

  // Clouds, aurora and launches can be slow or down; the first look waits
  // for none of them, only for where the user is and the ISS.
  testWidgets('a quick look waits for the ISS only, and takes wherever the phone last was', (t) async {
    final iss = File('test/fixtures/iss_omm.json').readAsStringSync();
    final asked = <String>[];
    final client = MockClient((req) {
      asked.add(req.url.host);
      return req.url.toString().contains('CATNR=25544')
          ? Future.value(http.Response(iss, 200))
          : Completer<http.Response>().future; // never answers
    });
    final here = _Here();
    final service = RefreshService(
      store: LocalStore(),
      notifications: _Notes(),
      celestrak: CelestrakClient(client: client),
      swpc: SwpcClient(client: client),
      meteo: OpenMeteoClient(client: client),
      launchLibrary: LaunchLibraryClient(client: client),
      location: here,
      catalog: () async => throw 'no sky in this test',
      issSeed: () async => const [],
    );
    RefreshReport? report;
    unawaited(service.run(quick: true).then((r) => report = r));
    await t.pump(const Duration(seconds: 1));
    expect(report, isNotNull, reason: 'nothing but the ISS was waited for');
    expect(report!.events, isNotEmpty);
    expect(asked.toSet(), {'celestrak.org'});
    expect(here.anyAge, [true]);
  });

  group('Celestrak out of reach on a first launch', () {
    // The shipped ISS with its epoch moved to [age] ago.
    Future<List<OmmRecord>> Function() seed(Duration age) => () async => [
          for (final j in jsonDecode(File('test/fixtures/iss_omm.json').readAsStringSync()) as List)
            OmmRecord.fromJson({
              ...(j as Map).cast<String, Object?>(),
              'EPOCH': DateTime.now().toUtc().subtract(age).toIso8601String().replaceAll('Z', ''),
            }),
        ];

    RefreshService offline(LocalStore store, _Notes notes, Future<List<OmmRecord>> Function() issSeed,
        {AlertPlanner planner = const AlertPlanner()}) {
      final down = MockClient((req) async => http.Response('down', 503));
      return RefreshService(
        store: store,
        notifications: notes,
        celestrak: CelestrakClient(client: down),
        swpc: SwpcClient(client: down),
        meteo: OpenMeteoClient(client: down),
        launchLibrary: LaunchLibraryClient(client: down),
        location: _Here(),
        catalog: () async => throw 'no sky in this test',
        issSeed: issSeed,
        planner: planner,
      );
    }

    Future<RefreshReport> settle(WidgetTester t, Future<RefreshReport> run) async {
      RefreshReport? report;
      unawaited(run.then((r) => report = r));
      for (var i = 0; i < 20 && report == null; i++) {
        await t.pump(const Duration(seconds: 5));
      }
      return report!;
    }

    // A first look beats an empty sky, but its times are only roughly
    // right: it never alerts (a false alarm is the one thing this app must
    // never do), isn't kept, and the next open tries Celestrak again.
    testWidgets('the shipped ISS gives a first look, marked approximate, that never alerts', (t) async {
      final store = LocalStore();
      final notes = _Notes();
      final planner = _Planner();
      final report = await settle(t, offline(store, notes, seed(const Duration(days: 2)), planner: planner).run());
      expect(report.approximate, isTrue);
      expect(report.events.where((e) => e.type == SkyEventType.iss), isNotEmpty);
      expect(planner.given, isNotNull);
      expect(planner.given!.where((e) => e.type == SkyEventType.iss || e.type == SkyEventType.issTransit), isEmpty);
      expect(notes.planned, isNotNull);
      expect(notes.planned!.where((a) => a.event.type == SkyEventType.iss || a.event.type == SkyEventType.issTransit),
          isEmpty);
      expect(await store.loadEvents(), isEmpty);
      expect(await store.loadLastRefresh(), isNull);
    });

    // A blocked or slow Celestrak held the first look's empty cards for
    // the whole quickLimit; a usable shipped ISS stands in after seedLimit.
    testWidgets('a quick look shows the shipped ISS after 2 s rather than waiting out 10 s', (t) async {
      final silent = MockClient((req) => Completer<http.Response>().future);
      final service = RefreshService(
        store: LocalStore(),
        notifications: _Notes(),
        celestrak: CelestrakClient(client: silent),
        swpc: SwpcClient(client: silent),
        meteo: OpenMeteoClient(client: silent),
        launchLibrary: LaunchLibraryClient(client: silent),
        location: _Here(),
        catalog: () async => throw 'no sky in this test',
        issSeed: seed(const Duration(days: 2)),
      );
      RefreshReport? report;
      unawaited(service.run(quick: true).then((r) => report = r));
      await t.pump(const Duration(milliseconds: 1900));
      expect(report, isNull, reason: 'a real ISS that comes quickly still wins');
      await t.pump(const Duration(milliseconds: 300));
      expect(report, isNotNull, reason: 'gone on after RefreshService.seedLimit');
      expect(report!.approximate, isTrue);
      expect(report!.events.where((e) => e.type == SkyEventType.iss), isNotEmpty);
      await t.pump(const Duration(minutes: 4)); // let the abandoned requests' own retries run out
    });

    testWidgets('a shipped ISS too old to trust shows nothing', (t) async {
      final report = await settle(t, offline(LocalStore(), _Notes(), seed(const Duration(days: 30))).run(quick: true));
      expect(report.approximate, isFalse);
      expect(report.events.where((e) => e.type == SkyEventType.iss), isEmpty);
    });
  });

  // Celestrak asks for each feed at most once a day; every phone forcing,
  // retrying or coming back at the same moment is how it gets hammered.
  group('Celestrak etiquette', () {
    // Celestrak answers [celestrak] for every feed (the ISS from the fixture
    // on 200); the other sources answer nothing useful.
    ({List<String> asked, RefreshService service}) world(LocalStore store, int celestrak) {
      final asked = <String>[];
      final iss = File('test/fixtures/iss_omm.json').readAsStringSync();
      final client = MockClient((req) async {
        asked.add(req.url.toString());
        if (req.url.host != 'celestrak.org') return http.Response('down', 503);
        if (celestrak != 200) return http.Response('no', celestrak);
        return http.Response(req.url.toString().contains('CATNR=25544') ? iss : '[]', 200);
      });
      return (
        asked: asked,
        service: RefreshService(
          store: store,
          notifications: _Notes(),
          celestrak: CelestrakClient(client: client),
          swpc: SwpcClient(client: client),
          meteo: OpenMeteoClient(client: client),
          launchLibrary: LaunchLibraryClient(client: client),
          location: _Here(),
          catalog: () async => throw 'no sky in this test',
          issSeed: () async => const [],
        ),
      );
    }

    Future<void> settle(WidgetTester t, Future<RefreshReport> run) async {
      var done = false;
      unawaited(run.whenComplete(() => done = true));
      for (var i = 0; i < 30 && !done; i++) {
        await t.pump(const Duration(seconds: 5));
      }
      expect(done, isTrue);
    }

    bool celestrak(String u) => u.contains('celestrak.org');

    // A relay nudge forces a refresh on every subscribed phone at once.
    testWidgets('a forced refresh leaves a feed fetched today alone, and still refreshes the weather', (t) async {
      final store = LocalStore();
      final first = world(store, 200);
      await settle(t, first.service.run());
      expect(first.asked.where((u) => u.contains('CATNR=25544')), hasLength(1));

      final forced = world(store, 200);
      await settle(t, forced.service.run(force: true));
      expect(forced.asked.where(celestrak), isEmpty);
      expect(forced.asked.where((u) => u.contains('open-meteo')), isNotEmpty, reason: 'force still means something');
    });

    testWidgets('a feed that failed rests instead of being asked on every open', (t) async {
      final store = LocalStore();
      final down = world(store, 503);
      await settle(t, down.service.run());
      expect(down.asked.where((u) => u.contains('CATNR=25544')), hasLength(3), reason: 'a 503 may be a glitch: retried');

      final again = world(store, 200);
      await settle(t, again.service.run(force: true));
      expect(again.asked.where(celestrak), isEmpty);
    });

    testWidgets('a refusal is asked once, not retried', (t) async {
      final store = LocalStore();
      final blocked = world(store, 403);
      await settle(t, blocked.service.run());
      expect(blocked.asked.where((u) => u.contains('CATNR=25544')), hasLength(1));
    });
  });

  group('LocalStore.celestrakDue', () {
    final now = DateTime.utc(2026, 11, 4, 12);
    CachedElements aged(Duration d) => CachedElements(fetchedAt: now.subtract(d), records: const []);

    test('rests 1 h, then 4 h, then a day after failures in a row, and a success ends it', () async {
      final store = LocalStore();
      Future<bool> dueAfter(Duration d) => store.celestrakDue('iss', null, now.add(d));
      await store.celestrakFailed('iss', now);
      expect(await dueAfter(const Duration(minutes: 59)), isFalse);
      expect(await dueAfter(const Duration(minutes: 61)), isTrue);
      await store.celestrakFailed('iss', now);
      expect(await dueAfter(const Duration(hours: 3, minutes: 59)), isFalse);
      expect(await dueAfter(const Duration(hours: 4, minutes: 1)), isTrue);
      await store.celestrakFailed('iss', now);
      expect(await dueAfter(const Duration(hours: 23, minutes: 59)), isFalse);
      await store.celestrakSucceeded('iss');
      await store.celestrakFailed('iss', now);
      expect(await dueAfter(const Duration(minutes: 61)), isTrue, reason: 'back to the shortest rest');
      expect(await store.celestrakDue('starlink', null, now), isTrue, reason: 'each feed rests on its own');
    });

    test('a refusal rests a day at once', () async {
      final store = LocalStore();
      await store.celestrakFailed('iss', now, refused: true);
      expect(await store.celestrakDue('iss', null, now.add(const Duration(hours: 23, minutes: 59))), isFalse);
    });

    // Phones that all downloaded after one event shouldn't all come back
    // at the same moment the next day.
    test('a cache is due between 24 and 25 h old, at a moment each install picks', () async {
      final at30 = <bool>{};
      for (var i = 0; i < 24; i++) {
        SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
        final store = LocalStore();
        expect(await store.celestrakDue('iss', aged(const Duration(hours: 23, minutes: 59)), now), isFalse);
        expect(await store.celestrakDue('iss', aged(const Duration(hours: 25, minutes: 1)), now), isTrue);
        final mid = await store.celestrakDue('iss', aged(const Duration(hours: 24, minutes: 30)), now);
        expect(await store.celestrakDue('iss', aged(const Duration(hours: 24, minutes: 30)), now), mid,
            reason: 'an install keeps its moment');
        at30.add(mid);
      }
      expect(at30, {true, false}, reason: 'installs differ (fails 1 time in ~8 million by chance)');
    });
  });
}
