/// "Tonight in 20 seconds": the coming night as a few full-screen frames,
/// in the order you'd meet them. Clouds first, then each thing worth going
/// out for, the bright planets, the Moon, and what to do next.
library;

import '../models/sky_event.dart';
import '../scheduling/alert_planner.dart';
import '../sky/tonight.dart';
import 'night_plan.dart';

sealed class StoryFrame {
  const StoryFrame();
}

/// Where the night stands: dark from when, and the clouds.
class OpeningFrame extends StoryFrame {
  const OpeningFrame(this.plan);
  final NightPlan? plan;
}

/// One event tonight. [locked] when it's Plus-only and there's no Plus,
/// so the frame can say what LookUp+ would have done about it.
class EventFrame extends StoryFrame {
  const EventFrame(this.event, {required this.locked});
  final SkyEvent event;
  final bool locked;
}

class PlanetFrame extends StoryFrame {
  const PlanetFrame(this.planet);
  final PlanetTonight planet;
}

class MoonFrame extends StoryFrame {
  const MoonFrame(this.moon);
  final MoonTonight moon;
}

/// The last frame. [upsell] is a real Plus-only event coming up, when
/// there's no Plus; otherwise the frame just leads on to the sky.
class EndFrame extends StoryFrame {
  const EndFrame({this.upsell});
  final SkyEvent? upsell;
}

/// Tonight's frames: events that start before the night ends (at most
/// [maxEvents]), up to two planets worth seeing, the Moon when it's up and
/// more than a sliver, and an end frame. Never through cloud: planets and
/// the Moon only appear with a "yes" verdict.
List<StoryFrame> tonightStory({
  required NightPlan? plan,
  required List<SkyEvent> events,
  required DateTime now,
  required bool isPlus,
  int maxEvents = 4,
}) {
  final u = now.toUtc();
  final until = plan?.window?.end ?? u.add(const Duration(hours: 18));
  final tonight = [
    for (final e in events)
      if (e.type.pushes && e.details['lookahead'] != true && e.end.isAfter(u) && e.start.isBefore(until)) e,
  ]..sort((a, b) => a.start.compareTo(b.start));
  final shown = tonight.take(maxEvents).toList();

  final planets = [
    for (final p in plan?.visiblePlanets ?? const <PlanetTonight>[])
      if (p.whyNot == null && (p.sighting?.verdict.yes ?? false)) p,
  ]..sort((a, b) => a.magnitude.compareTo(b.magnitude));

  final moon = plan?.moon;

  SkyEvent? upsell;
  if (!isPlus) {
    upsell = shown.where((e) => e.plusOnly).firstOrNull ?? AlertPlanner.plusOnlyAhead(events, u, max: 1).firstOrNull;
  }

  return [
    OpeningFrame(plan),
    for (final e in shown) EventFrame(e, locked: e.plusOnly && !isPlus),
    for (final p in planets.take(2)) PlanetFrame(p),
    if (moon != null && moon.illumination >= 0.08 && (moon.sighting?.verdict.yes ?? false)) MoonFrame(moon),
    EndFrame(upsell: upsell),
  ];
}
