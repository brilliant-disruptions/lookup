/// iOS Live Activity (Lock Screen + Dynamic Island countdown) through the
/// native channel in ios/Runner/AppDelegate.swift. No-op elsewhere, and
/// until the widget extension exists (docs/ios-widgets.md).
library;

import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../domain/models/sky_event.dart';
import '../domain/sky/direction.dart';
import '../ui/format.dart';

class LiveActivityService {
  const LiveActivityService();
  static const _channel = MethodChannel('lookup/live_activity');

  static bool get _ios {
    try {
      return Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  /// Start a countdown for an event that begins within 30 minutes.
  Future<void> startIfSoon(SkyEvent e, {DateTime? now}) async {
    if (!_ios) return;
    final until = e.start.difference((now ?? DateTime.now()).toUtc());
    if (until.isNegative || until > const Duration(minutes: 30)) return;
    try {
      await _channel.invokeMethod('start', {
        'title': eventTitle(e),
        'startMs': e.start.millisecondsSinceEpoch.toDouble(),
        'endMs': e.end.millisecondsSinceEpoch.toDouble(),
        'direction': 'Look ${compassWord(e.riseAzimuthDeg)}, ${elevationWord(e.peakElevationDeg)}',
      });
    } catch (_) {}
  }

  Future<void> markLive() => _call('update', {'phase': 'live'});
  Future<void> end() => _call('end');

  Future<void> _call(String m, [Map<String, Object?>? args]) async {
    if (!_ios) return;
    try {
      await _channel.invokeMethod(m, args);
    } catch (_) {}
  }
}
