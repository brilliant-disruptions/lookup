/// Night vision as the app shows it: red from sunset to sunrise where they
/// are, unless it's switched off in Settings ([nightVisionNow]).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/sky/night_safe.dart';
import '../domain/sky/sun.dart';
import 'providers.dart';

/// Whether the whole app is red right now.
final nightVisionOnProvider = Provider<bool>((ref) {
  final s = ref.watch(settingsProvider).value;
  if (s == null || !s.nightVision || s.latitude == null || s.longitude == null) return false;
  // Re-check the Sun once a minute.
  final minute = ref.watch(
    clockProvider.select((c) => c.value?.millisecondsSinceEpoch == null ? null : c.value!.millisecondsSinceEpoch ~/ 60000),
  );
  final at = minute == null ? DateTime.now().toUtc() : DateTime.fromMillisecondsSinceEpoch(minute * 60000, isUtc: true);
  return nightVisionNow(enabled: s.nightVision, sunAltitudeDeg: sunAltitudeDeg(at, s.latitude!, s.longitude!));
});
