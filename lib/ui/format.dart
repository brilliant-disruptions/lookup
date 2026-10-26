import 'package:intl/intl.dart';

import '../domain/models/sky_event.dart';
import '../domain/sky/direction.dart';

String fmtTime(DateTime utc) => DateFormat.jm().format(utc.toLocal());

/// To the second, for transits that last under one.
String fmtTimeSeconds(DateTime utc) => DateFormat.jms().format(utc.toLocal());

/// "0.8 s", "2.4 s".
String fmtSeconds(Duration d) => '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s';
String fmtDay(DateTime utc) {
  final l = utc.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(l.year, l.month, l.day);
  final diff = d.difference(today).inDays;
  final morning = l.hour < 12;
  if (diff == 0) return morning ? 'This morning' : 'Tonight';
  if (diff == 1) return morning ? 'Tomorrow morning' : 'Tomorrow night';
  if (diff == -1) return morning ? 'Yesterday morning' : 'Last night';
  if (diff.abs() >= 7) return DateFormat.MMMd().format(l); // "Nov 12"
  final day = DateFormat.EEEE().format(l);
  return morning ? '$day morning' : (diff < 0 ? '$day night' : day);
}

String fmtCountdown(Duration d) {
  if (d.isNegative) return 'now';
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  if (h >= 48) return '${d.inDays} days';
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
  return '${s}s';
}

String eventTitle(SkyEvent e) => switch (e.type) {
      SkyEventType.starlinkTrain => (e.details['label'] as String?) ?? e.type.label,
      SkyEventType.auroraOutlook => (e.details['headline'] as String?) ?? e.type.label,
      SkyEventType.meteorShower => '${e.details['shower'] ?? 'Meteor'} peak',
      SkyEventType.lunarEclipse || SkyEventType.planetPairing || SkyEventType.rocketLaunch =>
        (e.details['label'] as String?) ?? e.type.label,
      SkyEventType.issTransit => 'ISS crosses the ${e.details['body'] ?? 'Sun'}',
      SkyEventType.satellitePass => (e.details['name'] as String?) ?? e.type.label,
      SkyEventType.planetHighlight => (e.details['label'] as String?) ?? e.type.label,
      SkyEventType.skyObject => (e.details['name'] as String?) ?? e.type.label,
      _ => e.type.label,
    };

String eventSubtitle(SkyEvent e) {
  switch (e.type) {
    case SkyEventType.auroraOutlook:
      final kp = (e.details['kp'] as num?)?.toStringAsFixed(1);
      return 'Forecast Kp $kp · look north once it\'s fully dark';
    case SkyEventType.auroraNow:
      return 'Find a dark spot and look north';
    case SkyEventType.starlinkTrain:
      final n = e.details['count'];
      return 'A line of ~$n lights, ${describeArc(riseAzimuthDeg: e.riseAzimuthDeg, peakElevationDeg: e.peakElevationDeg, duration: e.duration)}';
    case SkyEventType.meteorShower:
      final moon = ((e.details['moonIllumination'] as num?) ?? 0) * 100;
      return 'Up to ~${e.details['perHour']} an hour, best around ${fmtTime(e.peak)} · Moon ${moon.round()}% lit';
    case SkyEventType.lunarEclipse:
      return 'The Moon, ${elevationWord(e.peakElevationDeg)} in the ${compassWord(e.peakAzimuthDeg)}. Deepest at ${fmtTime(e.peak)}';
    case SkyEventType.planetPairing:
      return '${e.details['separation']}° apart, ${elevationWord(e.peakElevationDeg)} in the ${compassWord(e.peakAzimuthDeg)} (${e.details['when']})';
    case SkyEventType.rocketLaunch:
      return '${e.details['name']} · ${e.details['distanceKm']} km away, low in the ${compassWord(e.peakAzimuthDeg)}';
    case SkyEventType.issTransit:
      return transitWhere(e);
    case SkyEventType.planetHighlight:
      final b = e.details['brightness'] as String?;
      return '${b == null ? '' : '${b[0].toUpperCase()}${b.substring(1)}, '}${elevationWord(e.peakElevationDeg)} in the ${compassWord(e.peakAzimuthDeg)}';
    case SkyEventType.skyObject:
      return '${elevationWord(e.peakElevationDeg)[0].toUpperCase()}${elevationWord(e.peakElevationDeg).substring(1)} in the ${compassWord(e.peakAzimuthDeg)}';
    case SkyEventType.satellitePass:
    case SkyEventType.iss:
    case SkyEventType.tiangong:
      final b = e.details['brightness'] as String?;
      final arc = describeArc(
          riseAzimuthDeg: e.riseAzimuthDeg,
          peakElevationDeg: e.peakElevationDeg,
          duration: e.duration);
      return b == null ? arc : '${b[0].toUpperCase()}${b.substring(1)}, $arc';
  }
}

String cloudWord(int? c) {
  if (c == null) return 'clouds unknown';
  if (c <= 20) return 'clear';
  if (c <= 60) return 'some cloud';
  return 'cloudy';
}

String eventEmoji(SkyEvent e) => switch (e.type) {
      SkyEventType.iss => '🛰️',
      SkyEventType.tiangong => '🛰️',
      SkyEventType.starlinkTrain => '✨',
      SkyEventType.auroraNow => '🌌',
      SkyEventType.auroraOutlook => '🌌',
      SkyEventType.meteorShower => '☄️',
      SkyEventType.lunarEclipse => '🌕',
      SkyEventType.planetPairing => '🪐',
      SkyEventType.rocketLaunch => '🚀',
      SkyEventType.issTransit => e.details['body'] == 'Moon' ? '🌕' : '☀️',
      SkyEventType.satellitePass => '🛰️',
      SkyEventType.planetHighlight => '🪐',
      SkyEventType.skyObject => '✨',
    };

String shareText(SkyEvent e, String? place) {
  final where = place == null ? '' : ' over $place';
  return switch (e.type) {
    SkyEventType.iss => 'Just watched the space station fly$where 🛰️ LookUp tapped me 10 minutes before.',
    SkyEventType.tiangong => 'Just watched Tiangong fly$where 🛰️ LookUp tapped me 10 minutes before.',
    SkyEventType.starlinkTrain => 'A Starlink train just crossed the sky$where ✨ LookUp told me when to step outside.',
    SkyEventType.auroraNow || SkyEventType.auroraOutlook => 'Aurora$where tonight 🌌 LookUp said to go look north.',
    SkyEventType.meteorShower => 'Caught the ${e.details['shower'] ?? 'meteor shower'}$where ☄️ LookUp told me when.',
    SkyEventType.lunarEclipse => 'Watched the lunar eclipse$where 🌕 LookUp tapped me in time.',
    SkyEventType.planetPairing => '${e.details['label']} side by side$where 🪐 Spotted with LookUp.',
    SkyEventType.rocketLaunch => 'Just watched a rocket launch$where 🚀 LookUp told me where to look.',
    SkyEventType.issTransit => 'Caught the space station crossing the ${e.details['body'] ?? 'Sun'}$where. It took ${fmtSeconds(transitCrossing(e))}.',
    SkyEventType.satellitePass => 'Watched ${e.details['name'] ?? 'a satellite'} cross the sky$where 🛰️ Spotted with LookUp.',
    SkyEventType.planetHighlight => '${e.details['label']}$where 🪐 Spotted with LookUp.',
    SkyEventType.skyObject => 'Found ${e.details['name'] ?? 'it'} in the sky$where ✨ with LookUp.',
  };
}

/// Verdict for something that already happened.
String pastVerdict(SkyEvent e) {
  final c = e.cloudCoverPercent;
  if (c == null) return 'Visible if it was clear';
  if (c <= 20) return 'Clear skies, it was visible';
  if (c <= 60) return 'Some cloud, partly visible';
  return 'Clouded out';
}

String pastTitle(SkyEvent e) => switch (e.type) {
      SkyEventType.auroraNow => 'Aurora strength reached',
      SkyEventType.starlinkTrain => (e.details['label'] as String?) ?? 'Starlink train',
      _ => eventTitle(e),
    };

Duration transitCrossing(SkyEvent e) => Duration(milliseconds: (e.details['crossingMs'] as num?)?.toInt() ?? 0);

/// "From right here at 3:14:07 PM" or "Go 12 km north-west · 3:14:07 PM".
String transitWhere(SkyEvent e) {
  final km = (e.details['travelKm'] as num?)?.toDouble() ?? 0;
  final when = fmtTimeSeconds(e.peak);
  final lasts = fmtSeconds(transitCrossing(e));
  if (km < 0.5) return 'Visible from right here at $when · lasts $lasts';
  return 'Go ${km.round()} km ${compassWord((e.details['travelBearingDeg'] as num?)?.toDouble() ?? 0)} · $when · lasts $lasts';
}
