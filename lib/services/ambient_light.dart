/// The light around the phone, for night vision's red strength, through
/// the native channel in MainActivity.kt (light sensor, lux) and
/// ios/Runner/AppDelegate.swift (screen brightness: iOS has no sensor API).
/// Only listened to while night vision is on.
library;

import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../domain/sky/night_vision.dart';

class AmbientLightService {
  const AmbientLightService();
  static const _channel = EventChannel('lookup/ambient_light');

  static bool get _mobile {
    try {
      return Platform.isAndroid || Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  /// Red strength (0–1). Nothing at all without a sensor: callers keep
  /// full red.
  Stream<double> redStrength() {
    if (!_mobile) return const Stream.empty();
    return _channel
        .receiveBroadcastStream()
        .map((e) {
          final m = e as Map;
          final lux = m['lux'] as num?;
          final screen = m['screen'] as num?;
          if (lux != null) return redStrengthFromLux(lux.toDouble());
          if (screen != null) return redStrengthFromScreen(screen.toDouble());
          return 1.0;
        })
        .distinct()
        .handleError((Object _) {});
  }
}
