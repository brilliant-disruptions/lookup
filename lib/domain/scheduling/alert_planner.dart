/// Turns the next 48 hours of events into a concrete list of notifications.
///
/// Rules (see spec §2, §5.5): type enabled, Plus gating, cloud gating, quiet
/// hours (with the aurora wake-me exception), max N alerts per local night,
/// lead time, optional go-now nudge, stable ids.
library;

import '../models/settings.dart';
import '../models/sky_event.dart';
import '../sky/direction.dart';

enum AlertKind { headsUp, goNow }

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
  }) {
    final nowUtc = now.toUtc();
    final limit = nowUtc.add(horizon);
    final candidates = events
        .where((e) => e.start.isAfter(nowUtc) && e.start.isBefore(limit))
        .where((e) => _typeEnabled(e.type, settings))
        .where((e) => settings.isPlus || !e.plusOnly)
        .where((e) => !settings.clearSkyOnly ||
            (e.cloudCoverPercent ?? 0) <= LookUpSettings.cloudyThresholdPercent)
        .where((e) => passesQuietHours(e, settings, utcOffsetMinutes))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

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
      final headsUpAt = e.start.subtract(Duration(minutes: settings.leadMinutes));
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

  static bool _typeEnabled(SkyEventType t, LookUpSettings s) => switch (t) {
        SkyEventType.iss => s.issEnabled,
        SkyEventType.tiangong => s.tiangongEnabled,
        SkyEventType.starlinkTrain => s.starlinkEnabled,
        SkyEventType.auroraNow => s.auroraEnabled,
        SkyEventType.auroraOutlook => false, // outlook is never pushed
      };

  /// Quiet hours block everything except aurora when wake-me is on.
  static bool passesQuietHours(
      SkyEvent e, LookUpSettings s, int utcOffsetMinutes) {
    final local = e.start.add(Duration(minutes: utcOffsetMinutes));
    final minuteOfDay = local.hour * 60 + local.minute;
    if (!s.quietHours.contains(minuteOfDay)) return true;
    return s.auroraWakeMe && e.type == SkyEventType.auroraNow;
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
    };
    return '$what in $leadMinutes min';
  }

  static String headsUpBody(SkyEvent e) {
    if (e.type == SkyEventType.auroraNow) {
      return 'Find a dark spot and look north. ${_cloudNote(e)}'.trim();
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
