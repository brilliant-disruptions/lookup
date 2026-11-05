/// Fetch what's stale → compute events → plan alerts → schedule them.
/// Every source failure is tolerated: the previous cache stands.
library;

import '../data/aurora_reports_client.dart';
import '../data/celestrak_client.dart';
import '../data/launch_library_client.dart';
import '../domain/scheduling/alert_tuning.dart';
import '../data/local_store.dart';
import '../data/open_meteo_client.dart';
import '../data/swpc_client.dart';
import '../domain/aurora/aurora_rules.dart';
import '../domain/aurora/seen_nearby.dart';
import '../domain/models/settings.dart';
import '../domain/models/sky_event.dart';
import '../domain/orbit/omm.dart';
import '../domain/scheduling/alert_planner.dart';
import '../domain/sky/catalog.dart';
import '../domain/sky/sun.dart';
import '../domain/weather/cloud_forecast.dart';
import 'event_pipeline.dart';
import 'location_service.dart';
import 'notification_service.dart';
import 'sky_catalog_loader.dart';

class RefreshReport {
  RefreshReport(
      {required this.events, required this.plan, required this.errors, this.recent = const [], this.approximate = false});
  final List<SkyEvent> events;
  final List<SkyEvent> recent;
  final List<PlannedAlert> plan;
  final List<String> errors;

  /// The ISS came from the copy shipped with the app (Celestrak out of
  /// reach and nothing cached): its times are approximate and alert nothing.
  final bool approximate;
  bool get ok => errors.isEmpty;
}

class RefreshService {
  RefreshService({
    required this.store,
    required this.notifications,
    CelestrakClient? celestrak,
    SwpcClient? swpc,
    OpenMeteoClient? meteo,
    LaunchLibraryClient? launchLibrary,
    LocationService? location,
    AuroraReportsClient? auroraReports,
    this.onRefreshed,
    this.pipeline = const EventPipeline(),
    this.planner = const AlertPlanner(),
    this.catalog = loadSkyCatalog,
    this.issSeed = loadIssSeed,
  })  : celestrak = celestrak ?? CelestrakClient(),
        swpc = swpc ?? SwpcClient(),
        meteo = meteo ?? OpenMeteoClient(),
        launchLibrary = launchLibrary ?? LaunchLibraryClient(),
        location = location ?? const LocationService(),
        auroraReports = auroraReports ?? (relayConfigured ? AuroraReportsClient() : null);

  final LocalStore store;
  final NotificationService notifications;
  final CelestrakClient celestrak;
  final SwpcClient swpc;
  final OpenMeteoClient meteo;
  final LaunchLibraryClient launchLibrary;
  final LocationService location;

  /// Seen near you; null when this build has no relay.
  final AuroraReportsClient? auroraReports;

  /// Called after each successful refresh (home-screen widgets). Errors
  /// there never fail the refresh.
  final Future<void> Function(LookUpSettings settings, List<SkyEvent> events)? onRefreshed;
  final EventPipeline pipeline;
  final AlertPlanner planner;

  /// The fixed sky, so alerts can say which bright things a pass goes near.
  final Future<SkyCatalog> Function() catalog;

  /// The ISS as shipped with the app, for a first look when Celestrak can't
  /// be reached and nothing is cached. Display only: never alerts.
  final Future<List<OmmRecord>> Function() issSeed;

  /// How old the shipped ISS may be and still give a first look. Past this
  /// its pass times drift too far to show.
  static const seedMaxAge = Duration(days: 21);

  /// Downloads in flight, by feed, so a prefetch and the refreshes after it
  /// share one request instead of asking the feed twice.
  final _inflight = <String, Future<Object?>>{};

  /// Fetches [key] once however many ask while it's in flight.
  Future<T> _shared<T>(String key, Future<T> Function() fetch) =>
      (_inflight[key] ??= fetch().whenComplete(() {
        _inflight.remove(key); // not returned: whenComplete would wait on it, i.e. on itself
      })) as Future<T>;

  /// What doesn't depend on where the user is (satellites, launches, the
  /// fixed sky), fetched while onboarding asks for location so the first
  /// look only waits for the location itself. Same staleness rules as
  /// [run], so it never asks a feed more often; failures are left to [run].
  Future<void> prefetch() async {
    final now = DateTime.now().toUtc();
    final settings = await store.loadSettings();
    final errors = <String>[];
    await (
      _elements('iss', _fetchIss, now: now, errors: errors),
      settings.tiangongEnabled
          ? _elements('tiangong', _fetchTiangong, now: now, errors: errors)
          : Future<List<OmmRecord>?>.value(),
      settings.launchesEnabled ? _launches(now: now, errors: errors) : Future.value(),
      catalog().then<Object?>((c) => c, onError: (_) => null),
    ).wait;
    // Last and biggest: not ahead of the ISS on a slow connection.
    if (settings.starlinkEnabled) await _elements('starlink', _fetchStarlink, now: now, errors: errors);
  }

  /// The shipped ISS, if it's recent enough to show; else null.
  Future<List<OmmRecord>?> _seed(DateTime now) async {
    try {
      final seed = await issSeed();
      if (seed.isNotEmpty && now.difference(seed.first.epoch) < seedMaxAge) return seed;
    } catch (_) {}
    return null;
  }

  Future<List<OmmRecord>> _fetchIss() => celestrak.fetchByCatalogNumber(Norad.iss);
  Future<List<OmmRecord>> _fetchTiangong() => celestrak.fetchByCatalogNumber(Norad.tiangong);

  Future<List<OmmRecord>> _fetchStarlink() async {
    // Keep only what we need: train-phase groups are a few hundred
    // records, not 11 k. Supplemental covers the newest launch.
    final all = await celestrak.fetchStarlink();
    List<OmmRecord> sup = const [];
    try {
      sup = await celestrak.fetchStarlinkSupplemental();
    } catch (_) {}
    return _trimStarlink([...all, ...sup]);
  }

  /// Cached elements for [key], fetched first when [LocalStore.celestrakDue]
  /// says so; there is no forcing it, as every phone forcing a fetch is how
  /// Celestrak gets hammered. [limit] caps the wait without stopping the
  /// download: whoever asks next gets it.
  Future<List<OmmRecord>?> _elements(String key, Future<List<OmmRecord>> Function() fetch,
      {required DateTime now, required List<String> errors, bool cacheOnly = false, Duration? limit}) async {
    final cached = await store.loadElements(key);
    if (cacheOnly || !await store.celestrakDue(key, cached, now)) return cached?.records;
    try {
      var got = _shared(key, () async {
        final List<OmmRecord> recs;
        try {
          recs = await fetch();
        } catch (e) {
          await store.celestrakFailed(key, now, refused: e is CelestrakRefused);
          rethrow;
        }
        // Nothing to keep (or nothing left after trimming Starlink) rests the
        // feed like a failure: unsaved, it would be due on every refresh.
        if (recs.isEmpty) {
          await store.celestrakFailed(key, now);
        } else {
          await store.celestrakSucceeded(key);
          await store.saveElements(key, recs, now);
        }
        return recs;
      });
      if (limit != null) got = got.timeout(limit);
      final recs = await got;
      if (recs.isNotEmpty) return recs;
    } catch (e) {
      errors.add('$key: $e');
    }
    return cached?.records;
  }

  Future<List<Map<String, Object?>>> _launches(
      {required DateTime now, required List<String> errors, bool force = false, bool cacheOnly = false}) async {
    var launchesCache = await store.loadLaunches();
    if (!cacheOnly &&
        (force || launchesCache == null || now.difference(launchesCache.fetchedAt) > launchesMaxAge)) {
      try {
        final raw = await _shared('launches', () async {
          final raw = await launchLibrary.fetchUpcomingRaw();
          await store.saveLaunches(raw, now);
          return raw;
        });
        launchesCache = (fetchedAt: now, raw: raw);
      } catch (e) {
        errors.add('launches: $e');
      }
    }
    return launchesCache?.raw ?? const [];
  }

  static const cloudsMaxAge = Duration(hours: 6);
  static const auroraMaxAge = Duration(minutes: 30);
  static const launchesMaxAge = Duration(hours: 6);

  /// How long a quick refresh waits on any one source before going without
  /// it. A source that never answers would otherwise hold the first look for
  /// minutes (60 s timeout × 3 tries); the full refresh after it tries again.
  static const quickLimit = Duration(seconds: 10);

  /// How long the first look waits for the ISS when the shipped copy is
  /// recent enough to show instead; the full refresh brings the real one.
  static const seedLimit = Duration(seconds: 2);

  /// [quick] is onboarding's first look: it waits only for a location (any
  /// the phone already has) and the ISS (at most [seedLimit] when the
  /// shipped copy can stand in, else [quickLimit]). Everything else is whatever is cached: clouds, aurora,
  /// launches and Starlink fill in with the full refresh that must follow.
  /// It schedules nothing and doesn't mark the refresh done.
  Future<RefreshReport> run({bool force = false, bool allowLocationPrompt = false, bool quick = false}) async {
    final errors = <String>[];
    final now = DateTime.now().toUtc();
    var settings = await store.loadSettings();

    final fix = await location.resolve(settings, allowPrompt: allowLocationPrompt, anyAge: quick);
    if (fix == null) {
      return RefreshReport(events: const [], plan: const [], errors: ['no location']);
    }
    if (settings.locationMode == LocationMode.auto &&
        (settings.latitude != fix.lat || settings.longitude != fix.lon)) {
      settings = settings.copyWith(latitude: fix.lat, longitude: fix.lon);
      await store.saveSettings(settings);
    }

    // Read before the ISS so the first look knows how long to wait for it.
    final seed = quick ? await _seed(now) : null;

    Future<CloudForecast?> fetchClouds() async {
      var clouds = await store.loadClouds();
      if (quick) return clouds;
      final cloudsMoved = clouds != null &&
          ((clouds.latitude - fix.lat).abs() > 0.2 ||
              (clouds.longitude - fix.lon).abs() > 0.2);
      if (force || clouds == null || cloudsMoved || clouds.isStale(now, maxAge: cloudsMaxAge)) {
        try {
          clouds = await meteo.fetchCloudForecast(fix.lat, fix.lon);
          await store.saveClouds(clouds);
        } catch (e) {
          errors.add('clouds: $e');
        }
      }
      return clouds;
    }

    Future<AuroraSnapshot?> fetchAurora() async {
      var aurora = await store.loadAurora();
      if (!quick &&
          settings.auroraEnabled &&
          (force || aurora == null || now.difference(aurora.fetchedAt) > auroraMaxAge)) {
        try {
          // All three at once; the forecast alone decides whether there's a snapshot.
          final kpNowF = swpc.fetchEstimatedKpNow()..ignore();
          final ovationF = swpc.fetchOvationProbabilityAt(fix.lat, fix.lon)..ignore();
          final forecast = await swpc.fetchKpForecast();
          double? kpNow;
          var ovation = 0;
          try {
            kpNow = await kpNowF;
            ovation = await ovationF;
          } catch (e) {
            errors.add('aurora-now: $e');
          }
          aurora = AuroraSnapshot(
              fetchedAt: now, kpNow: kpNow, forecast: forecast, ovationProbability: ovation);
          await store.saveAurora(aurora);
        } catch (e) {
          errors.add('aurora: $e');
        }
      }
      return aurora;
    }

    Future<SkyCatalog?> loadCatalog() async {
      try {
        return await catalog();
      } catch (_) {
        return null; // no landmarks this time; everything else stands
      }
    }

    // The sources don't depend on each other, so they download together:
    // the wait is the slowest one, not the sum of them all.
    var (iss, tiangong, starlink, clouds, aurora, launchesRaw, sky) = await (
      _elements('iss', _fetchIss, now: now, errors: errors, limit: quick ? (seed != null ? seedLimit : quickLimit) : null),
      settings.tiangongEnabled
          ? _elements('tiangong', _fetchTiangong, now: now, errors: errors, cacheOnly: quick)
          : Future<List<OmmRecord>?>.value(),
      settings.starlinkEnabled
          ? _elements('starlink', _fetchStarlink, now: now, errors: errors, cacheOnly: quick)
          : Future<List<OmmRecord>?>.value(),
      fetchClouds(),
      fetchAurora(),
      settings.launchesEnabled
          ? _launches(now: now, errors: errors, force: force, cacheOnly: quick)
          : _launches(now: now, errors: errors, cacheOnly: true),
      loadCatalog(),
    ).wait;

    // Celestrak out of reach on a first launch: the shipped ISS, if it's
    // recent enough, rather than an empty sky.
    var approximate = false;
    if (iss == null || iss.isEmpty) {
      final shipped = seed ?? await _seed(now);
      if (shipped != null) {
        iss = shipped;
        approximate = true;
      }
    }
    final launches = LaunchLibraryClient.parse(launchesRaw);

    // Learned thresholds from "what got in the way?" answers.
    final tuning = AlertTuning.from([for (final f in await store.loadFeedback()) f.toSighting()], now: now);
    final tuned = tuning.apply(settings);

    // Seen near you: ask the relay only when it could matter: switched on,
    // offered here, dark, and the aurora within reach of the model.
    var reports = const <AuroraReport>[];
    final relay = auroraReports;
    final kpNow = aurora?.kpNow;
    if (relay != null &&
        settings.seenNearby &&
        settings.auroraEnabled &&
        kpNow != null &&
        seenNearbyOffered(fix.lat, fix.lon) &&
        kpNow >= kpNeededAt(fix.lat, fix.lon) - const CrowdRules().kpSlack &&
        isDark(now, fix.lat, fix.lon)) {
      try {
        reports = await relay.nearby(fix.lat, fix.lon);
      } catch (e) {
        errors.add('seen-near-you: $e');
      }
    }

    final events = pipeline.build(PipelineInputs(
      auroraReports: reports,
      catalog: sky,
      launches: launches,
      settings: tuned,
      now: now,
      iss: iss,
      tiangong: tiangong,
      starlink: starlink,
      clouds: clouds,
      aurora: aurora,
    ));
    // Approximate times aren't kept: the next open tries Celestrak again.
    if (!approximate) await store.saveEvents(events);
    final recent = pipeline.buildRecent(PipelineInputs(
      settings: settings,
      now: now,
      iss: iss,
      tiangong: tiangong,
      starlink: starlink,
      clouds: clouds,
      aurora: aurora,
    ));
    if (!approximate) await store.saveRecent(recent);
    if (quick) {
      // A first look: the full refresh after it schedules and updates widgets.
      return RefreshReport(events: events, plan: const [], errors: errors, recent: recent, approximate: approximate);
    }

    final offset = NotificationService.utcOffsetMinutes();
    // Never alert from the shipped ISS: its times are only roughly right.
    final plan = planner.plan(
        events: approximate
            ? [for (final e in events) if (e.type != SkyEventType.iss && e.type != SkyEventType.issTransit) e]
            : events,
        settings: tuned, now: now, utcOffsetMinutes: offset, tuning: tuning);
    try {
      final previous = await store.loadPlannedIds();
      final scheduled = await notifications.applyPlan(plan, previous);
      await store.savePlannedIds(scheduled);
      await _fireAuroraNow(events, settings, offset);
    } catch (e) {
      errors.add('schedule: $e');
    }
    if (onRefreshed != null && !approximate) {
      try {
        await onRefreshed!(settings, events);
      } catch (e) {
        errors.add('after-refresh: $e');
      }
    }

    // Without any ISS elements (first launch + a failed fetch) there is
    // nothing to show; don't mark the refresh done so the next app open
    // retries instead of waiting out the 3-hour staleness window. The same
    // for the shipped ISS.
    if (!approximate && iss != null && iss.isNotEmpty) await store.saveLastRefresh(now);
    return RefreshReport(events: events, plan: plan, errors: errors, recent: recent, approximate: approximate);
  }

  /// "Aurora now" can't be scheduled ahead; show it immediately, once per
  /// 3-hour bucket (the event id carries the bucket).
  Future<void> _fireAuroraNow(
      List<SkyEvent> events, LookUpSettings settings, int offset) async {
    if (!settings.isPlus) return;
    for (final e in events.where((e) => e.type == SkyEventType.auroraNow)) {
      if (!AlertPlanner.passesQuietHours(e, settings, offset)) continue;
      final id = AlertPlanner.notificationIdFor(e.id, AlertKind.headsUp);
      final already = await store.loadPlannedIds();
      if (already.contains(id)) continue;
      await notifications.showNow(
        id: id,
        title: AlertPlanner.auroraNowTitle(e),
        body: AlertPlanner.headsUpBody(e, miles: settings.usesMiles),
        payload: e.id,
        kind: AlertKind.goNow, // already happening: no "remind me later"
      );
      await store.savePlannedIds({...already, id});
    }
  }

  static List<OmmRecord> _trimStarlink(List<OmmRecord> all) {
    // Deduplicate by name (supplemental + catalog overlap), prefer freshest.
    final byName = <String, OmmRecord>{};
    for (final r in all) {
      final prev = byName[r.objectName];
      if (prev == null || r.epoch.isAfter(prev.epoch)) byName[r.objectName] = r;
    }
    return [
      for (final r in byName.values)
        if (r.revAtEpoch <= 600 && r.meanMotion >= 15.5) r,
    ];
  }
}
