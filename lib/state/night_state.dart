/// Night vision as the app shows it: red from sunset to sunrise where they
/// are, unless it's switched off in Settings ([nightVisionNow]), as red as
/// the light around the phone and "How red" say ([nightVisionStrength]).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/sky/night_safe.dart';
import '../domain/sky/night_vision.dart';
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

/// Auto's red right now: what the light around the phone says, full red
/// until the first reading (or with no sensor at all).
final autoRedProvider = Provider.autoDispose<double>((ref) => ref.watch(ambientRedProvider).value ?? 1);

/// While someone drags "How red", the red they're dragging to, so the whole
/// app follows the finger (by day too, as a preview). Null otherwise.
class NightVisionDrag extends Notifier<double?> {
  @override
  double? build() => null;
  void to(double? v) => state = v;
}

final nightVisionDragProvider = NotifierProvider<NightVisionDrag, double?>(NightVisionDrag.new);

/// How red the screen is when night vision is on (0 is true colours).
final nightVisionStrengthProvider = Provider.autoDispose<double>((ref) {
  final drag = ref.watch(nightVisionDragProvider);
  if (drag != null) return drag;
  final s = ref.watch(settingsProvider).value;
  if (s == null) return 1;
  return nightVisionStrength(
    auto: s.nightVisionFollowsLight,
    autoRed: s.nightVisionFollowsLight ? ref.watch(autoRedProvider) : 1,
    nudge: s.nightVisionNudge,
    level: s.nightVisionLevel,
  );
});

/// Whether the screen is actually red right now (on, and not true colours
/// in a lit room), or being previewed from "How red".
final nightVisionRedProvider = Provider.autoDispose<bool>((ref) {
  if (ref.watch(nightVisionDragProvider) != null) return true;
  return ref.watch(nightVisionOnProvider) && ref.watch(nightVisionStrengthProvider) > 0.02;
});

/// Saves where "How red" was left: a nudge to Auto, or the fixed level.
Future<void> saveHowRed(WidgetRef ref, double target) async {
  final s = ref.read(settingsProvider).value;
  if (s == null) return;
  final autoRed = ref.read(autoRedProvider);
  await ref.read(settingsProvider.notifier).edit((x) => x.nightVisionFollowsLight
      ? x.copyWith(nightVisionNudge: nudgeFor(target: target, autoRed: autoRed))
      : x.copyWith(nightVisionLevel: target.clamp(0.0, 1.0)));
}
