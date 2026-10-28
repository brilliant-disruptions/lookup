/// Turns the next 48 hours of events into a concrete list of notifications.
///
/// Rules (see spec §2, §5.5): type enabled, Plus gating, cloud gating, quiet
/// hours (with the aurora wake-me exception), max N alerts per local night,
/// lead time, optional go-now nudge, stable ids.
library;

import '../models/settings.dart';
import '../models/sky_event.dart';
import '../sky/direction.dart';
import '../events/standing_alerts.dart' show milkyWayTripLead;
import 'alert_tuning.dart';

/// [snooze] is the user's "Remind me in 5 min", never planned here.
enum AlertKind { headsUp, goNow, snooze }

class PlannedAlert {
  const PlannedAlert({
    required this.notificationId,
    required this.event,
    required this.fireAt,
    required this.kind,
    required this.title,
    required this.body,
  });

  final int notificationId;
  final SkyEvent event;
  final DateTime fireAt; // UTC
  final AlertKind kind;
  final String title;
  final String body;

  @override
  String toString() =>
      'PlannedAlert(#$notificationId ${kind.name} ${fireAt.toIso8601String()} ${event.id})';
}

class AlertPlanner {
  const AlertPlanner();

  /// [utcOffsetMinutes] is the device's offset for quiet-hours and "night"
  /// bucketing. Domain stays free of timezone databases.
  List<PlannedAlert> plan({
    required List<SkyEvent> events,
    required LookUpSettings settings,
    required DateTime now,
    required int utcOffsetMinutes,
    Duration horizon = const Duration(hours: 48),
    AlertTuning tuning = AlertTuning.neutral,
  }) {
    final nowUtc = now.toUtc();
    final limit = nowUtc.add(horizon);
    final candidates = events
        .where((e) => e.start.isAfter(nowUtc) && e.start.isBefore(limit))
        .where((e) => e.type.pushes && _typeEnabled(e.type, settings))
        .where((e) => settings.isPlus || !e.plusOnly)
        .where((e) => !settings.clearSkyOnly ||
            (e.cloudCoverPercent ?? 0) <= tuning.cloudCutoffPercent)
        .where((e) => passesQuietHours(e, settings, utcOffsetMinutes))
        .toList()
      // Moments first (a pass, a shower), then by score. A favourite or a
      // Milky Way night is up for hours, so its score would swamp a
      // four-minute pass; it only takes a slot nothing fleeting wants.
      ..sort((a, b) {
        final t = _standing(a).compareTo(_standing(b));
        return t != 0 ? t : b.score.compareTo(a.score);
      });

    // Nightly cap: best-scored events win.
    final perNight = <String, int>{};
    final chosen = <SkyEvent>[];
    for (final e in candidates) {
      final night = _nightKey(e.peak, utcOffsetMinutes);
      final n = perNight[night] ?? 0;
      if (n >= settings.maxAlertsPerNight) continue;
      perNight[night] = n + 1;
      chosen.add(e);
    }
    chosen.sort((a, b) => a.start.compareTo(b.start));

    final out = <PlannedAlert>[];
    for (final e in chosen) {
      final headsUpAt = e.start.subtract(leadFor(e, settings));
      if (headsUpAt.isAfter(nowUtc)) {
        out.add(PlannedAlert(
          notificationId: notificationIdFor(e.id, AlertKind.headsUp),
          event: e,
          fireAt: headsUpAt,
          kind: AlertKind.headsUp,
          title: headsUpTitle(e, settings.leadMinutes),
          body: headsUpBody(e),
        ));
      }
      final goNowAt = e.start.subtract(const Duration(minutes: 1));
      if (settings.goNowNudge &&
          _standing(e) == 0 &&
          !e.isEstimate &&
          settings.leadMinutes > 1 &&
          goNowAt.isAfter(nowUtc)) {
        out.add(PlannedAlert(
          notificationId: notificationIdFor(e.id, AlertKind.goNow),
          event: e,
          fireAt: goNowAt,
          kind: AlertKind.goNow,
          title: 'Go outside now',
          body: goNowBody(e),
        ));
      }
    }
    out.sort((a, b) => a.fireAt.compareTo(b.fireAt));
    return out;
  }

  /// "Remind me in 5 min" from a heads-up: fires [by] from [now] but never
  /// later than a minute before the start. Null when the event is too close
  /// for a reminder to help (the go-now tap covers that).
  static PlannedAlert? snooze(SkyEvent e, DateTime now, {Duration by = const Duration(minutes: 5)}) {
    final nowUtc = now.toUtc();
    var at = nowUtc.add(by);
    final latest = e.start.subtract(const Duration(minutes: 1));
    if (at.isAfter(latest)) at = latest;
    if (at.difference(nowUtc) < const Duration(minutes: 1)) return null;
    final lead = e.start.difference(at).inMinutes;
    return PlannedAlert(
      notificationId: notificationIdFor(e.id, AlertKind.snooze),
      event: e,
      fireAt: at,
      kind: AlertKind.snooze,
      title: headsUpTitle(e, lead),
      body: headsUpBody(e),
    );
  }

  static int _standing(SkyEvent e) =>
      e.type == SkyEventType.favourite || e.type == SkyEventType.milkyWayNight ? 1 : 0;

  /// Most taps come [LookUpSettings.leadMinutes] before; a Milky Way night
  /// somewhere else comes hours ahead, to leave time to get there.
  static Duration leadFor(SkyEvent e, LookUpSettings s) =>
      e.type == SkyEventType.milkyWayNight && e.details['here'] != true
          ? milkyWayTripLead
          : Duration(minutes: s.leadMinutes);

  static bool _typeEnabled(SkyEventType t, LookUpSettings s) => switch (t) {
        SkyEventType.iss => s.issEnabled,
        SkyEventType.tiangong => s.tiangongEnabled,
        SkyEventType.starlinkTrain => s.starlinkEnabled,
        SkyEventType.auroraNow => s.auroraEnabled,
        SkyEventType.auroraOutlook => false, // outlook is never pushed
        SkyEventType.meteorShower => s.meteorsEnabled,
        SkyEventType.lunarEclipse => s.eclipsesEnabled,
        SkyEventType.planetPairing || SkyEventType.planetHighlight => s.pairingsEnabled,
        SkyEventType.rocketLaunch => s.launchesEnabled,
        SkyEventType.favourite => s.favouriteAlertsEnabled,
        SkyEventType.milkyWayNight => s.milkyWayEnabled,
        // Listed for planning, never pushed.
        SkyEventType.issTransit || SkyEventType.satellitePass || SkyEventType.skyObject => false,
      };

  /// Quiet hours block everything except aurora and lunar eclipses when
  /// wake-me is on (both are rare and worth getting up for).
  static bool passesQuietHours(
      SkyEvent e, LookUpSettings s, int utcOffsetMinutes) {
    // A trip tap is judged by when it arrives, not when the night starts.
    final at = e.type == SkyEventType.milkyWayNight && e.details['here'] != true
        ? e.start.subtract(milkyWayTripLead)
        : e.start;
    final local = at.add(Duration(minutes: utcOffsetMinutes));
    final minuteOfDay = local.hour * 60 + local.minute;
    if (!s.quietHours.contains(minuteOfDay)) return true;
    return s.auroraWakeMe &&
        (e.type == SkyEventType.auroraNow || e.type == SkyEventType.lunarEclipse);
  }

  /// Local calendar date of "the night", where anything before local noon
  /// belongs to the previous evening.
  static String _nightKey(DateTime utc, int utcOffsetMinutes) {
    final local = utc.add(Duration(minutes: utcOffsetMinutes - 12 * 60));
    return '${local.year}-${local.month}-${local.day}';
  }

  /// Stable, positive 31-bit id from the event key and kind (FNV-1a).
  static int notificationIdFor(String eventId, AlertKind kind) {
    var h = 0x811C9DC5;
    for (final c in '$eventId|${kind.name}'.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h & 0x7FFFFFFF;
  }

  static String headsUpTitle(SkyEvent e, int leadMinutes) {
    final what = switch (e.type) {
      SkyEventType.iss => 'ISS flyover',
      SkyEventType.tiangong => 'Tiangong flyover',
      SkyEventType.starlinkTrain =>
        (e.details['label'] as String?) ?? 'Starlink train',
      SkyEventType.auroraNow => 'Aurora now',
      SkyEventType.auroraOutlook => 'Aurora tonight',
      SkyEventType.meteorShower => '${e.details['shower'] ?? 'Meteor shower'} tonight',
      SkyEventType.lunarEclipse => (e.details['label'] as String?) ?? 'Lunar eclipse',
      SkyEventType.planetPairing => (e.details['label'] as String?) ?? 'Planet pairing',
      SkyEventType.rocketLaunch => 'Rocket launch',
      SkyEventType.issTransit => 'ISS crosses the ${e.details['body'] ?? 'Sun'}',
      SkyEventType.satellitePass => (e.details['name'] as String?) ?? 'Satellite pass',
      SkyEventType.planetHighlight => (e.details['label'] as String?) ?? 'Planet highlight',
      SkyEventType.skyObject => (e.details['name'] as String?) ?? 'Sky object',
      SkyEventType.favourite => '${e.details['name']} at its best',
      SkyEventType.milkyWayNight =>
        e.details['here'] == true ? 'Milky Way night' : 'Milky Way night at ${e.details['place']}',
    };
    if (e.type == SkyEventType.planetHighlight) return what;
    if (e.type == SkyEventType.milkyWayNight) return e.details['here'] == true ? '$what from ${_hm(e.start)}' : '$what tonight';
    if (e.type == SkyEventType.meteorShower) return what;
    return '$what in $leadMinutes min';
  }

  static String headsUpBody(SkyEvent e) {
    if (e.type == SkyEventType.auroraNow) {
      return 'Find a dark spot and look north. ${_cloudNote(e)}'.trim();
    }
    switch (e.type) {
      case SkyEventType.meteorShower:
        final rate = e.details['perHour'];
        final moon = (e.details['moonIllumination'] as num?) ?? 0;
        final moonNote = (e.details['moonUp'] == true && moon > 0.5) ? ' The Moon will wash out the faint ones.' : '';
        return 'Up to ~$rate an hour from a dark spot, best around ${_hm(e.peak)}. Look up anywhere, away from lights.$moonNote ${_cloudNote(e)}'.trim();
      case SkyEventType.lunarEclipse:
        return 'Look ${compassWord(e.peakAzimuthDeg)} at the Moon, ${elevationWord(e.peakElevationDeg)}. Deepest at ${_hm(e.peak)}. ${_cloudNote(e)}'.trim();
      case SkyEventType.planetPairing:
        final sep = e.details['separation'];
        return '$sep° apart, ${elevationWord(e.peakElevationDeg)} in the ${compassWord(e.peakAzimuthDeg)}. Two bright points side by side. ${_cloudNote(e)}'.trim();
      case SkyEventType.planetHighlight:
        final b = e.details['brightness'] as String?;
        return '${e.details['planet']} is ${b ?? 'bright'}, ${elevationWord(e.peakElevationDeg)} in the ${compassWord(e.peakAzimuthDeg)}. ${_cloudNote(e)}'.trim();
      case SkyEventType.favourite:
        return 'Look ${compassWord(e.peakAzimuthDeg)}, ${elevationWord(e.peakElevationDeg)}. ${_cloudNote(e)}'.trim();
      case SkyEventType.milkyWayNight:
        final until = _hm(e.end);
        if (e.details['here'] == true) {
          return 'The Moon\'s down and it\'s clear until $until. Face ${compassWord(e.peakAzimuthDeg)}, away from lights, and give your eyes 20 minutes.';
        }
        return 'Moonless and clear there ${_hm(e.start)}–$until. A good night for the trip.';
      case SkyEventType.rocketLaunch:
        final dist = e.details['distanceKm'];
        final name = e.details['name'] ?? 'A rocket';
        return '$name, $dist km away. Look ${compassWord(e.peakAzimuthDeg)}, low on the horizon. Launch times slip; we update if it moves. ${_cloudNote(e)}'.trim();
      default:
        break;
    }
    final b = e.details['brightness'] as String?;
    final arc = describeArc(
      riseAzimuthDeg: e.riseAzimuthDeg,
      peakElevationDeg: e.peakElevationDeg,
      duration: e.duration,
    );
    final count = e.details['count'] as int?;
    final lead = count != null ? 'A line of ~$count lights, ' : '';
    final hedge = e.isEstimate ? ' (estimate)' : '';
    final bright = b != null && count == null ? '${_cap(b)}, ' : '';
    return '$lead$bright$arc$hedge. ${_cloudNote(e)}'.trim();
  }

  static String goNowBody(SkyEvent e) =>
      'Look ${compassWord(e.riseAzimuthDeg)}. ${_cap(elevationWord(e.peakElevationDeg))} at its best.';

  /// Device-local clock time, e.g. "2:40 AM". Domain stays timezone-free by
  /// using the event's own offset-free UTC→local conversion.
  static String _hm(DateTime utc) {
    final l = utc.toLocal();
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    return '$h:${l.minute.toString().padLeft(2, '0')} ${l.hour < 12 ? 'AM' : 'PM'}';
  }

  static String _cloudNote(SkyEvent e) {
    final c = e.cloudCoverPercent;
    if (c == null) return '';
    if (c <= 20) return 'Clear skies.';
    if (c <= LookUpSettings.cloudyThresholdPercent) return 'Some cloud ($c%).';
    return 'Cloudy ($c%) — might not see it.';
  }

  static String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
