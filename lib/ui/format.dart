import 'package:intl/intl.dart';

import '../domain/models/sky_event.dart';
import '../domain/sky/direction.dart';

String fmtTime(DateTime utc) => DateFormat.jm().format(utc.toLocal());
String fmtDay(DateTime utc) {
  final l = utc.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(l.year, l.month, l.day);
  final diff = d.difference(today).inDays;
  if (diff == 0) return 'Tonight';
  if (diff == 1) return 'Tomorrow';
  return DateFormat.EEEE().format(l);
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
    };

String shareText(SkyEvent e, String? place) {
  final where = place == null ? '' : ' over $place';
  return switch (e.type) {
    SkyEventType.iss => 'Just watched the space station fly$where 🛰️ LookUp tapped me 10 minutes before.',
    SkyEventType.tiangong => 'Just watched Tiangong fly$where 🛰️ LookUp tapped me 10 minutes before.',
    SkyEventType.starlinkTrain => 'A Starlink train just crossed the sky$where ✨ LookUp told me when to step outside.',
    SkyEventType.auroraNow || SkyEventType.auroraOutlook => 'Aurora$where tonight 🌌 LookUp said to go look north.',
  };
}
