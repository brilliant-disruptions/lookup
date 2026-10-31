/// "Your first three": a new user's starter quest, built from their own sky.
/// A space station (or Starlink) pass, a planet and a star pattern, each on
/// the first night it's really easy to see. It turns "wait for a pass" into
/// something to do tonight, and every tick lands in the sky log.
///
/// Pure. Planets and stars only count as "easy" on a great or good verdict
/// (the same bar as favourites), so it never sends anyone out into cloud.
library;

import '../models/sky_event.dart';
import '../plan/night_plan.dart';
import '../sky/catalog.dart';
import '../sky/tonight.dart';
import '../sky/visibility.dart';
import 'sighting.dart';
import 'sky_log.dart';

enum StarterKind { pass, planet, stars }

class StarterStep {
  const StarterStep({required this.kind, required this.done, this.event, this.skyId, this.night, this.sighting});
  final StarterKind kind;
  final bool done;

  /// For [StarterKind.pass]: the pass to catch.
  final SkyEvent? event;

  /// For planets and stars: what to find ("planet:saturn", "con:Ori", "m45"),
  /// which night (0 = tonight) and its sighting that night.
  final String? skyId;
  final int? night;
  final SkySighting? sighting;

  /// Nothing to aim for in the next fortnight (and not done yet).
  bool get waiting => !done && event == null && skyId == null;
}

abstract final class StarterSky {
  /// Passes that count: things that fly over.
  static const passTypes = {SkyEventType.iss, SkyEventType.tiangong, SkyEventType.starlinkTrain, SkyEventType.satellitePass};

  /// People who've already logged this many are past a starter quest.
  static const seasoned = 10;

  static bool isPass(Sighting s) => passTypes.contains(s.inferredType);
  static bool isPlanet(Sighting s) => s.eventId.startsWith('obj:planet:') || s.inferredType == SkyEventType.planetHighlight;

  /// A constellation, cluster, galaxy… anything fixed but the Moon and planets.
  static bool isStars(Sighting s) =>
      s.eventId.startsWith('obj:') && !s.eventId.startsWith('obj:planet:') && s.eventId != 'obj:${SkyId.moon}';

  static ({bool pass, bool planet, bool stars}) progress(Iterable<Sighting> seen) =>
      (pass: seen.any(isPass), planet: seen.any(isPlanet), stars: seen.any(isStars));

  static bool _all(({bool pass, bool planet, bool stars}) p) => p.pass && p.planet && p.stars;

  /// True when the sighting of [eventId] is the one that, in time order,
  /// first made all three done.
  static bool completedBy(SkyLog log, String eventId) {
    final chrono = log.seen.reversed.toList(); // oldest first
    for (var i = 0; i < chrono.length; i++) {
      if (_all(progress(chrono.take(i + 1)))) return chrono[i].eventId == eventId;
    }
    return false;
  }

  /// The quest to show, or null once it's done or for seasoned users.
  static List<StarterStep>? plan({
    required SkyLog log,
    required Iterable<SkyEvent> events,
    required List<NightPlan> nights,
    required DateTime now,
    required bool isPlus,
  }) {
    final p = progress(log.seen);
    if (_all(p) || log.total >= seasoned) return null;
    final u = now.toUtc();

    SkyEvent? pass;
    if (!p.pass) {
      final ahead =
          events
              .where(
                (e) =>
                    passTypes.contains(e.type) &&
                    e.type.pushes &&
                    (isPlus || !e.plusOnly) &&
                    e.start.isAfter(u) &&
                    e.start.isBefore(u.add(const Duration(days: 14))),
              )
              .toList()
            ..sort((a, b) => a.start.compareTo(b.start));
      pass = ahead.firstOrNull;
    }

    bool easy(SkySighting? s) => s != null && (s.verdict == Seeability.great || s.verdict == Seeability.good);

    ({String id, int night, SkySighting sighting})? planet;
    if (!p.planet) {
      for (final (i, n) in nights.indexed) {
        final up = [
          for (final pl in n.planets)
            if (pl.whyNot == null && easy(pl.sighting)) pl,
        ]..sort((a, b) => a.magnitude.compareTo(b.magnitude));
        if (up.isNotEmpty) {
          planet = (id: SkyId.planet(up.first.planet), night: i, sighting: up.first.sighting!);
          break;
        }
      }
    }

    ({String id, int night, SkySighting sighting})? stars;
    if (!p.stars) {
      for (final (i, n) in nights.indexed) {
        // A famous pattern first (best placed first), else a naked-eye showpiece.
        final con = n.constellations.where((c) => easy(c.sighting)).firstOrNull;
        if (con != null) {
          stars = (id: SkyId.constellation(con.constellation.id), night: i, sighting: con.sighting);
          break;
        }
        final show = n.showpieces.where((s) => s.showpiece.aid == Aid.eyes && easy(s.sighting)).firstOrNull;
        if (show != null) {
          stars = (id: show.showpiece.id, night: i, sighting: show.sighting);
          break;
        }
      }
    }

    return [
      StarterStep(kind: StarterKind.pass, done: p.pass, event: pass),
      StarterStep(kind: StarterKind.planet, done: p.planet, skyId: planet?.id, night: planet?.night, sighting: planet?.sighting),
      StarterStep(kind: StarterKind.stars, done: p.stars, skyId: stars?.id, night: stars?.night, sighting: stars?.sighting),
    ];
  }
}
