/// Night vision as the app shows it: the switch, or red by itself on the
/// screens used outside once it's dark where they are ([nightVisionNow]).
library;

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/sky/night_safe.dart';
import '../domain/sky/sun.dart';
import 'providers.dart';

/// How many outside screens (finder, Look up now, You caught it, camera
/// view) are open. Leaving the last one forgets any choice made there.
class OutsideScreens extends Notifier<int> {
  @override
  int build() => 0;
  void enter() => state = state + 1;
  void exit() {
    state = math.max(0, state - 1);
    if (state == 0) ref.read(nightOverrideProvider.notifier).set(null);
  }
}

final outsideScreensProvider = NotifierProvider<OutsideScreens, int>(OutsideScreens.new);

/// The eye button pressed on an outside screen: on or off until they leave.
class NightOverride extends Notifier<bool?> {
  @override
  bool? build() => null;
  void set(bool? v) => state = v;
}

final nightOverrideProvider = NotifierProvider<NightOverride, bool?>(NightOverride.new);

/// Whether the whole app is red right now.
final nightVisionOnProvider = Provider<bool>((ref) {
  final s = ref.watch(settingsProvider).value;
  if (s == null) return false;
  final outside = ref.watch(outsideScreensProvider) > 0;
  double? sun;
  if (outside && s.nightVisionAuto && s.latitude != null && s.longitude != null) {
    // Re-check the Sun once a minute while they're out.
    final minute = ref.watch(
      clockProvider.select((c) => c.value?.millisecondsSinceEpoch == null ? null : c.value!.millisecondsSinceEpoch ~/ 60000),
    );
    final at = minute == null ? DateTime.now().toUtc() : DateTime.fromMillisecondsSinceEpoch(minute * 60000, isUtc: true);
    sun = sunAltitudeDeg(at, s.latitude!, s.longitude!);
  }
  return nightVisionNow(
    manual: s.nightVision,
    auto: s.nightVisionAuto,
    outside: outside,
    sunAltitudeDeg: sun,
    override: ref.watch(nightOverrideProvider),
  );
});
