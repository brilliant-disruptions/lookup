/// The rules behind onboarding's first look at the sky (Follow Pip): which
/// moment of their sky to show, the day-and-night model the slider teaches
/// with, a line about each thing Pip finds, and which real pass to preview.
/// Nothing here logs a sighting: practice and preview catches never reach
/// the Log. Pure.
library;

import 'dart:math' as math;

import '../models/sky_event.dart';

/// How long after the sky turns dark (sun at −6°) the first look is set, so
/// it shows a properly dark sky with the bright things out.
const firstLookAfterDusk = Duration(minutes: 40);

/// The moment of their sky to show: right now if it's already dark (inside
/// tonight's window; a plan made after dark starts its window at that
/// moment), else tonight a little after it gets dark. [window] is tonight's
/// dark hours (NightPlan.window); with none (polar summer) it's now.
({DateTime at, bool isNow}) firstLookTime(DateTime now, ({DateTime start, DateTime end})? window) {
  final u = now.toUtc();
  // No dark hours (polar summer), or a window that's already over (a plan
  // from another night): never name a time that's gone. Now.
  if (window == null || !u.isBefore(window.end.toUtc())) return (at: u, isNow: true);
  if (!u.isBefore(window.start.toUtc())) return (at: u, isNow: true);
  return (at: window.start.toUtc().add(firstLookAfterDusk), isNow: false);
}

/// What the slider shows at an hour of the day.
enum StationSight {
  /// The Sun is up: far too bright to see it.
  day,

  /// Dark where you are and the station still in sunlight: there it is.
  visible,

  /// Dark, and the station in Earth's shadow: it vanishes.
  shadow,
}

/// The teaching model: you on top of the Earth, the station overhead at
/// [orbitRadii] Earth radii (drawn high so the window is easy to find; not
/// to scale), the Sun going round once a day, noon overhead. Dark enough
/// once the Sun is 6° below your horizon.
StationSight stationSight(double hour, {double orbitRadii = 1.25}) {
  final a = (90 + (hour - 12) * 15) * math.pi / 180; // the Sun's direction
  final sunUp = math.sin(a); // its height above your horizon
  if (sunUp > -math.sin(6 * math.pi / 180)) return StationSight.day;
  // The station at (0, k): in the shadow if it's on the night side and
  // within one Earth radius of the line through the Earth away from the Sun.
  final along = orbitRadii * math.sin(a), across = (orbitRadii * math.cos(a)).abs();
  return along < 0 && across < 1 ? StationSight.shadow : StationSight.visible;
}

/// One line about what Pip just found.
String firstLookFact(String id, String name) => switch (id) {
      'moon' => 'About 384,000 km away. Its light takes about 1.3 seconds to reach you.',
      'planet:venus' => 'The brightest planet: sunlight off thick clouds. It\'s never far from the Sun, so look near dusk or dawn.',
      'planet:jupiter' => 'The biggest planet, hundreds of millions of km away. Planets shine steadily; stars twinkle.',
      'planet:saturn' => 'Its rings are there, but you need a small telescope to see them. A steady golden point.',
      'planet:mars' => 'Reddish and steady. Every two years or so it swings close to us and gets much brighter.',
      'planet:mercury' => 'The closest planet to the Sun, only ever low in the twilight. Few people have seen it.',
      _ => 'One of the sky\'s showpieces. Pip can find it for you any night.',
    };

/// The pass to preview in fast-forward: the next space station pass over
/// them in the coming [within] (free alerts cover it), or none.
SkyEvent? passToPreview(Iterable<SkyEvent> events, DateTime now, {Duration within = const Duration(days: 3)}) {
  final u = now.toUtc();
  SkyEvent? best;
  for (final e in events) {
    if (e.type != SkyEventType.iss || e.details['past'] == true) continue;
    if (!e.start.isAfter(u) || e.start.isAfter(u.add(within))) continue;
    if (best == null || e.start.isBefore(best.start)) best = e;
  }
  return best;
}
