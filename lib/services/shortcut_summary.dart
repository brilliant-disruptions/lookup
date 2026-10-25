/// What Siri says for "When's the next pass in LookUp?". The app writes the
/// next few events as sentences; the iOS App Intent (ios/Runner/
/// LookUpIntents.swift) reads them from UserDefaults and picks the first
/// one that hasn't ended, so the answer stays right between refreshes.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/sky_event.dart';
import '../domain/sky/direction.dart';
import '../ui/format.dart';

/// Key the Swift side reads (SharedPreferencesAsync stores keys verbatim in
/// UserDefaults.standard).
const shortcutKey = 'siri_upcoming';

String spokenSummary(SkyEvent e) {
  final when = '${fmtDay(e.start).toLowerCase()} at ${fmtTime(e.start)}';
  final face = e.type == SkyEventType.iss || e.type == SkyEventType.tiangong || e.type == SkyEventType.starlinkTrain
      ? e.riseAzimuthDeg
      : e.peakAzimuthDeg;
  final what = switch (e.type) {
    SkyEventType.iss => 'The space station passes over',
    SkyEventType.tiangong => 'Tiangong passes over',
    SkyEventType.starlinkTrain => 'A Starlink train passes over',
    SkyEventType.auroraNow => 'Aurora is possible right now,',
    SkyEventType.meteorShower => 'The ${e.details['shower'] ?? 'meteor shower'} peaks',
    _ => eventTitle(e),
  };
  final cloud = (e.cloudCoverPercent ?? 0) > 60 ? ' Clouds may get in the way.' : '';
  if (e.type == SkyEventType.auroraNow) return '$what look north from somewhere dark.$cloud';
  return '$what $when. Look ${compassWord(face)}, ${elevationWord(e.peakElevationDeg)}.$cloud';
}

List<Map<String, Object?>> shortcutPayload(List<SkyEvent> events, {int max = 6}) => [
      for (final e in events.where((e) => e.type.pushes && e.details['past'] != true).take(max))
        {'text': spokenSummary(e), 'startMs': e.start.millisecondsSinceEpoch, 'endMs': e.end.millisecondsSinceEpoch},
    ];

Future<void> saveShortcutSummary(List<SkyEvent> events, [SharedPreferencesAsync? prefs]) async {
  try {
    await (prefs ?? SharedPreferencesAsync()).setString(shortcutKey, jsonEncode(shortcutPayload(events)));
  } catch (_) {
    // Siri is a nicety; never fail a refresh over it.
  }
}
