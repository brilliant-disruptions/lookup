/// Fetch what's stale → compute events → plan alerts → schedule them.
/// Every source failure is tolerated: the previous cache stands.
library;

import '../data/celestrak_client.dart';
import '../data/launch_library_client.dart';
import '../domain/scheduling/alert_tuning.dart';
import '../data/local_store.dart';
import '../data/open_meteo_client.dart';
import '../data/swpc_client.dart';
import '../domain/models/settings.dart';
import '../domain/models/sky_event.dart';
import '../domain/orbit/omm.dart';
import '../domain/scheduling/alert_planner.dart';
import 'event_pipeline.dart';
import 'location_service.dart';
import 'notification_service.dart';

class RefreshReport {
  RefreshReport({required this.events, required this.plan, required this.errors, this.recent = const []});
  final List<SkyEvent> events;
  final List<SkyEvent> recent;
  final List<PlannedAlert> plan;
  final List<String> errors;
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
    this.onRefreshed,
    this.pipeline = const EventPipeline(),
    this.planner = const AlertPlanner(),
  })  : celestrak = celestrak ?? CelestrakClient(),
        swpc = swpc ?? SwpcClient(),
        meteo = meteo ?? OpenMeteoClient(),
        launchLibrary = launchLibrary ?? LaunchLibraryClient(),
        location = location ?? const LocationService();

  final LocalStore store;
  final NotificationService notifications;
  final CelestrakClient celestrak;
  final SwpcClient swpc;
  final OpenMeteoClient meteo;
  final LaunchLibraryClient launchLibrary;
  final LocationService location;

  /// Called after each successful refresh (home-screen widgets). Errors
  /// there never fail the refresh.
  final Future<void> Function(LookUpSettings settings, List<SkyEvent> events)? onRefreshed;
  final EventPipeline pipeline;
  final AlertPlanner planner;

  static const elementsMaxAge = Duration(hours: 24);
  static const cloudsMaxAge = Duration(hours: 6);
  static const auroraMaxAge = Duration(minutes: 30);
  static const launchesMaxAge = Duration(hours: 6);

  Future<RefreshReport> run({bool force = false, bool allowLocationPrompt = false}) async {
    final errors = <String>[];
    final now = DateTime.now().toUtc();
    var settings = await store.loadSettings();

    final fix = await location.resolve(settings, allowPrompt: allowLocationPrompt);
    if (fix == null) {
      return RefreshReport(events: const [], plan: const [], errors: ['no location']);
    }
    if (settings.locationMode == LocationMode.auto &&
        (settings.latitude != fix.lat || settings.longitude != fix.lon)) {
      settings = settings.copyWith(latitude: fix.lat, longitude: fix.lon);
      await store.saveSettings(settings);
    }

    Future<List<OmmRecord>?> elements(
        String key, Future<List<OmmRecord>> Function() fetch) async {
      final cached = await store.loadElements(key);
      if (!force && cached != null && !cached.isOlderThan(elementsMaxAge, now)) {
        return cached.records;
      }
      try {
        final recs = await fetch();
        if (recs.isNotEmpty) {
          await store.saveElements(key, recs, now);
          return recs;
        }
      } catch (e) {
        errors.add('$key: $e');
      }
      return cached?.records;
    }

    final iss = await elements('iss', () => celestrak.fetchByCatalogNumber(Norad.iss));
    final tiangong = settings.tiangongEnabled
        ? await elements('tiangong', () => celestrak.fetchByCatalogNumber(Norad.tiangong))
        : null;
    final starlink = settings.starlinkEnabled
        ? await elements('starlink', () async {
            // Keep only what we need: train-phase groups are a few hundred
            // records, not 11 k. Supplemental covers the newest launch.
            final all = await celestrak.fetchStarlink();
            List<OmmRecord> sup = const [];
            try {
              sup = await celestrak.fetchStarlinkSupplemental();
            } catch (_) {}
            return _trimStarlink([...all, ...sup]);
          })
        : null;

    var clouds = await store.loadClouds();
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

    var aurora = await store.loadAurora();
    if (settings.auroraEnabled &&
        (force || aurora == null || now.difference(aurora.fetchedAt) > auroraMaxAge)) {
      try {
        final forecast = await swpc.fetchKpForecast();
        double? kpNow;
        var ovation = 0;
        try {
          kpNow = await swpc.fetchEstimatedKpNow();
          ovation = await swpc.fetchOvationProbabilityAt(fix.lat, fix.lon);
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

    var launchesCache = await store.loadLaunches();
    if (settings.launchesEnabled &&
        (force || launchesCache == null || now.difference(launchesCache.fetchedAt) > launchesMaxAge)) {
      try {
        final raw = await launchLibrary.fetchUpcomingRaw();
        await store.saveLaunches(raw, now);
        launchesCache = (fetchedAt: now, raw: raw);
      } catch (e) {
        errors.add('launches: $e');
      }
    }
    final launches = LaunchLibraryClient.parse(launchesCache?.raw ?? const []);

    // Learned thresholds from "what got in the way?" answers.
    final tuning = AlertTuning.from([for (final f in await store.loadFeedback()) f.toSighting()], now: now);
    final tuned = tuning.apply(settings);

    final events = pipeline.build(PipelineInputs(
      launches: launches,
      settings: tuned,
      now: now,
      iss: iss,
      tiangong: tiangong,
      starlink: starlink,
      clouds: clouds,
      aurora: aurora,
    ));
    await store.saveEvents(events);
    final recent = pipeline.buildRecent(PipelineInputs(
      settings: settings,
      now: now,
      iss: iss,
      tiangong: tiangong,
      starlink: starlink,
      clouds: clouds,
      aurora: aurora,
    ));
    await store.saveRecent(recent);

    final offset = NotificationService.utcOffsetMinutes();
    final plan = planner.plan(
        events: events, settings: tuned, now: now, utcOffsetMinutes: offset, tuning: tuning);
    try {
      final previous = await store.loadPlannedIds();
      final scheduled = await notifications.applyPlan(plan, previous);
      await store.savePlannedIds(scheduled);
      await _fireAuroraNow(events, settings, offset);
    } catch (e) {
      errors.add('schedule: $e');
    }
    if (onRefreshed != null) {
      try {
        await onRefreshed!(settings, events);
      } catch (e) {
        errors.add('after-refresh: $e');
      }
    }

    // Without any ISS elements (first launch + a failed fetch) there is
    // nothing to show; don't mark the refresh done so the next app open
    // retries instead of waiting out the 3-hour staleness window.
    if (iss != null && iss.isNotEmpty) await store.saveLastRefresh(now);
    return RefreshReport(events: events, plan: plan, errors: errors, recent: recent);
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
        title: 'Aurora now',
        body: AlertPlanner.headsUpBody(e),
        payload: e.id,
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
