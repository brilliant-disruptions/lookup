/// The user's sky log: what they've seen, and the badges (patches) it earns.
///
/// Badges come in four shapes:
/// - **once**: earned by one catch (Train spotter, Blood Moon);
/// - **levels**: bronze, silver, gold at set counts (Station spotter at 1,
///   5 and 25 passes; Regular at 10, 25 and 50 catches);
/// - **collections**: slots to fill (the five planets you can see without a
///   telescope, four looks of the Moon);
/// - **secrets**: shown only as a riddle until earned.
/// Plus **seasonal** patches, one per meteor shower per year
/// ("Geminids 2026"), made from the catches themselves.
///
/// Only a catch earns anything (the Log holds catches and "missed it"
/// answers; only "seen" counts), and none of it is LookUp+.
library;

import 'dart:math' as math;

import '../models/sky_event.dart';
import '../sky/tonight.dart' show MoonPhase, moonPhase;
import 'sighting.dart';

/// What's on the patch.
enum BadgeArt {
  pip,
  firstLight,
  station,
  regular,
  planets,
  moonPhases,
  overhead,
  venus,
  train,
  aurora,
  meteor,
  bloodMoon,
  eclipse,
  rocket,
  bothStations,
  owl,
  transit,
  upPastThree,
  doubleNight,
}

enum BadgeTier {
  bronze('Bronze'),
  silver('Silver'),
  gold('Gold');

  const BadgeTier(this.label);
  final String label;
}

/// One slot of a collection.
class BadgeSlot {
  const BadgeSlot(this.label, {this.got = false});
  final String label;
  final bool got;
}

class Badge {
  const Badge(
    this.id,
    this.title,
    this.description, {
    required this.art,
    this.steps = const [],
    this.goals,
    this.count = 0,
    this.slots,
    this.secret = false,
    this.riddle,
    this.season,
  });

  final String id;
  final String title;

  /// How to earn it, in words (never degrees).
  final String description;
  final BadgeArt art;

  /// When each step was reached: one step for most badges, one per level
  /// for levelled ones. Empty until earned.
  final List<DateTime> steps;

  /// Levels: the counts for bronze, silver and gold.
  final List<int>? goals;

  /// How many towards [goals] so far.
  final int count;

  /// Collections: the slots and which are filled.
  final List<BadgeSlot>? slots;

  /// Shown only as [riddle] until earned.
  final bool secret;
  final String? riddle;

  /// Seasonal: the best night it's for.
  final DateTime? season;

  DateTime? get earnedAt => steps.isEmpty ? null : steps.first;

  /// When it last went up a step (earned, or a new level).
  DateTime? get lastStepAt => steps.isEmpty ? null : steps.last;
  bool get earned => steps.isNotEmpty;

  /// Bronze, silver or gold, for levelled badges once earned.
  BadgeTier? get tier => goals == null || steps.isEmpty ? null : BadgeTier.values[math.min(steps.length, 3) - 1];

  /// A secret not yet found: show the riddle, not the title.
  bool get hidden => secret && !earned;

  /// Towards the next step: (got, of), or null when there's nothing left
  /// to count (earned once-only badges, gold, a full collection).
  ({int got, int of})? get progress {
    if (goals case final g?) {
      final next = g.where((x) => x > count).firstOrNull;
      return next == null ? null : (got: count, of: next);
    }
    if (slots case final s?) {
      final got = s.where((x) => x.got).length;
      return got == s.length ? null : (got: got, of: s.length);
    }
    return null;
  }

  /// "Station spotter · Silver", or just the title.
  String get fullTitle => tier == null ? title : '$title · ${tier!.label}';

  Badge _with({List<DateTime>? steps, int? count, List<BadgeSlot>? slots}) => Badge(id, title, description,
      art: art,
      steps: steps ?? this.steps,
      goals: goals,
      count: count ?? this.count,
      slots: slots ?? this.slots,
      secret: secret,
      riddle: riddle,
      season: season);
}

/// The planets you can see without a telescope, in the collection's order.
const planetSlots = ['Mercury', 'Venus', 'Mars', 'Jupiter', 'Saturn'];

/// The looks of the Moon the collection asks for.
const moonSlots = ['Crescent', 'Half', 'Gibbous', 'Full'];

class SkyLog {
  SkyLog._({required this.seen, required this.counts, required this.badges, required this.hitRate});

  /// Seen events, newest first.
  final List<Sighting> seen;
  final Map<SkyEventType, int> counts;

  /// The patches, in shelf order; earned seasonal ones at the end.
  final List<Badge> badges;

  /// Share of answered alerts the user actually saw (null with < 3 answers).
  final double? hitRate;

  int get total => seen.length;
  int get earnedCount => badges.where((b) => b.earned).length;

  static const _defs = <Badge>[
    // The first one, earned by setting up: something on the shelf from day one.
    Badge('looked-up', 'Looked up', 'Set LookUp up to watch your sky.', art: BadgeArt.pip),
    Badge('first-light', 'First light', 'Catch your first thing in the sky with Pip.', art: BadgeArt.firstLight),
    Badge('station-spotter', 'Station spotter', 'Catch the space station. Bronze at 1, silver at 5, gold at 25.',
        art: BadgeArt.station, goals: [1, 5, 25]),
    Badge('regular', 'Regular', 'Catch 10 things for bronze, 25 for silver, 50 for gold.', art: BadgeArt.regular, goals: [10, 25, 50]),
    Badge('planet-set', 'Planet set', 'Catch all five planets you can see without a telescope.', art: BadgeArt.planets),
    Badge('moon-phases', 'Every Moon', 'Catch the Moon as a crescent, half, gibbous and full.', art: BadgeArt.moonPhases),
    Badge('overhead', 'Straight up', 'Catch a pass that goes nearly straight over your head.', art: BadgeArt.overhead),
    Badge('venus-bright', 'Venus-bright', 'Catch something as bright as Venus.', art: BadgeArt.venus),
    Badge('train-spotter', 'Train spotter', 'Catch a Starlink train: a line of lights, one after another.', art: BadgeArt.train),
    Badge('aurora-chaser', 'Aurora chaser', 'Catch an aurora.', art: BadgeArt.aurora),
    Badge('meteor-watcher', 'Meteor watcher', 'Catch a meteor shower on its best night.', art: BadgeArt.meteor),
    Badge('eclipse', 'Blood Moon', 'Catch a total eclipse of the Moon.', art: BadgeArt.bloodMoon),
    Badge('shadow', 'In the shadow', 'Catch an eclipse of the Sun (with eclipse glasses).', art: BadgeArt.eclipse),
    Badge('liftoff', 'Liftoff', 'Catch a rocket launch climbing up your sky.', art: BadgeArt.rocket),
    Badge('both-stations', 'Both stations', 'Catch the space station and Tiangong.', art: BadgeArt.bothStations),
    Badge('night-owl', 'Night owl', 'Catch something between midnight and 4 AM.', art: BadgeArt.owl),
    Badge('transit', 'Silhouette', 'Catch the station crossing the Sun or Moon.', art: BadgeArt.transit),
    Badge('up-past-three', 'Up past three', 'Caught something between 3 and 4 AM.',
        art: BadgeArt.upPastThree, secret: true, riddle: 'Pip knows one you only get by staying up very late.'),
    Badge('double-night', 'Double night', 'Caught two different things on one night.',
        art: BadgeArt.doubleNight, secret: true, riddle: 'Two things, one night.'),
  ];

  /// [onboardedAt] is when setting up finished: the "Looked up" badge.
  factory SkyLog.from(List<Sighting> all, {DateTime? onboardedAt}) {
    final seen = [...all.where((s) => s.seen)]..sort((a, b) => b.at.compareTo(a.at));
    final counts = <SkyEventType, int>{};
    for (final s in seen) {
      final t = s.inferredType;
      if (t != null) counts[t] = (counts[t] ?? 0) + 1;
    }
    // Steps happen at the moment each condition first became true (chronological).
    final chrono = seen.reversed.toList();
    final steps = <String, List<DateTime>>{
      if (onboardedAt != null) 'looked-up': [onboardedAt],
    };
    void step(String id, DateTime at) => (steps[id] ??= []).add(at);
    void once(String id, bool cond, DateTime at) {
      if (cond && !steps.containsKey(id)) step(id, at);
    }

    final running = <SkyEventType, int>{};
    final planets = <String>{}, moons = <String>{};
    final nights = <String, Set<String>>{};
    final seasonal = <String, Badge>{};
    for (var i = 0; i < chrono.length; i++) {
      final s = chrono[i];
      final t = s.inferredType;
      if (t != null) running[t] = (running[t] ?? 0) + 1;
      final local = (s.eventTime ?? s.at).toLocal();

      once('first-light', true, s.at);
      final iss = running[SkyEventType.iss] ?? 0;
      if (t == SkyEventType.iss && const [1, 5, 25].contains(iss)) step('station-spotter', s.at);
      if (const [10, 25, 50].contains(i + 1)) step('regular', s.at);

      if (planetOf(s) case final p?) {
        planets.add(p);
        once('planet-set', planets.length == planetSlots.length, s.at);
      }
      if (moonLookOf(s) case final m?) {
        moons.add(m);
        once('moon-phases', moons.length == moonSlots.length, s.at);
      }

      final pass = t == SkyEventType.iss || t == SkyEventType.tiangong || t == SkyEventType.starlinkTrain;
      once('overhead', pass && (s.peakElevationDeg ?? 0) >= 75, s.at);
      once('venus-bright', (s.magnitude ?? 99) <= -3.5, s.at);
      once('train-spotter', t == SkyEventType.starlinkTrain, s.at);
      once('aurora-chaser', t == SkyEventType.auroraNow || t == SkyEventType.auroraOutlook, s.at);
      once('meteor-watcher', t == SkyEventType.meteorShower, s.at);
      once('eclipse', t == SkyEventType.lunarEclipse, s.at);
      once('shadow', t == SkyEventType.solarEclipse, s.at);
      once('liftoff', t == SkyEventType.rocketLaunch, s.at);
      once('both-stations', iss > 0 && (running[SkyEventType.tiangong] ?? 0) > 0, s.at);
      once('night-owl', local.hour < 4, s.at);
      once('transit', t == SkyEventType.issTransit, s.at);
      once('up-past-three', local.hour == 3, s.at);
      final things = nights.putIfAbsent(nightKey(local), () => <String>{})..add(s.eventId);
      once('double-night', things.length >= 2, s.at);

      if (showerOf(s) case (final code, final year)) {
        seasonal.putIfAbsent('season-$code-$year', () => seasonPatch(code, year, earnedAt: s.at));
      }
    }

    final badges = [
      for (final b in _defs)
        b._with(
          steps: steps[b.id] ?? const [],
          count: switch (b.id) {
            'station-spotter' => counts[SkyEventType.iss] ?? 0,
            'regular' => seen.length,
            _ => 0,
          },
          slots: switch (b.id) {
            'planet-set' => [for (final p in planetSlots) BadgeSlot(p, got: planets.contains(p))],
            'moon-phases' => [for (final m in moonSlots) BadgeSlot(m, got: moons.contains(m))],
            _ => null,
          },
        ),
      ...seasonal.values,
    ];
    final answered = all.length;
    return SkyLog._(
      seen: seen,
      counts: counts,
      badges: badges,
      hitRate: answered >= 3 ? seen.length / answered : null,
    );
  }

  /// This season's patches not yet earned: the meteor showers in [upcoming]
  /// within [within] of [now], soonest first, each with its best night.
  List<Badge> comingSeason(Iterable<SkyEvent> upcoming, DateTime now, {Duration within = const Duration(days: 60)}) {
    final u = now.toUtc();
    final have = {for (final b in badges) b.id};
    final out = <String, Badge>{};
    for (final e in upcoming) {
      if (e.type != SkyEventType.meteorShower || e.end.isBefore(u) || e.peak.isAfter(u.add(within))) continue;
      final m = RegExp(r'^meteor-([A-Z]+):(\d{4})').firstMatch(e.id);
      if (m == null) continue;
      final id = 'season-${m.group(1)}-${m.group(2)}';
      if (have.contains(id)) continue;
      out.putIfAbsent(id, () => seasonPatch(m.group(1)!, int.parse(m.group(2)!), season: e.peak));
    }
    return out.values.toList()..sort((a, b) => a.season!.compareTo(b.season!));
  }
}

/// Which planet a catch is of, from its id ("obj:planet:jupiter" from the
/// sky camera, "planet-jupiter-…" from a planet alert).
String? planetOf(Sighting s) {
  final m = RegExp(r'^(?:obj:planet:|planet-)([a-z]+)').firstMatch(s.eventId);
  if (m == null) return null;
  final name = m.group(1)!;
  return planetSlots.where((p) => p.toLowerCase() == name).firstOrNull;
}

/// Which look of the Moon a catch is: crescent, half, gibbous or full.
/// The Moon in the sky camera ("obj:moon…"), a full Moon rising, or the
/// Moon in a lunar eclipse (always full).
String? moonLookOf(Sighting s) {
  final t = s.inferredType;
  if (t == SkyEventType.fullMoonRise || t == SkyEventType.lunarEclipse) return 'Full';
  if (!s.eventId.startsWith('obj:moon')) return null;
  return switch (moonPhase((s.eventTime ?? s.at).toUtc())) {
    MoonPhase.newMoon => null, // can't be seen
    MoonPhase.waxingCrescent || MoonPhase.waningCrescent => 'Crescent',
    MoonPhase.firstQuarter || MoonPhase.lastQuarter => 'Half',
    MoonPhase.waxingGibbous || MoonPhase.waningGibbous => 'Gibbous',
    MoonPhase.full => 'Full',
  };
}

/// A meteor-shower catch's (code, year), from "meteor-GEM:2026".
(String, int)? showerOf(Sighting s) {
  final m = RegExp(r'^meteor-([A-Z]+):(\d{4})').firstMatch(s.eventId);
  return m == null ? null : (m.group(1)!, int.parse(m.group(2)!));
}

/// The night a moment belongs to: before noon counts as the night before.
String nightKey(DateTime local) {
  final d = local.subtract(const Duration(hours: 12));
  return '${d.year}-${d.month}-${d.day}';
}

/// Shower names by IMO code.
const showerNames = {
  'QUA': 'Quadrantids',
  'LYR': 'Lyrids',
  'ETA': 'Eta Aquariids',
  'PER': 'Perseids',
  'DRA': 'Draconids',
  'ORI': 'Orionids',
  'LEO': 'Leonids',
  'GEM': 'Geminids',
  'URS': 'Ursids',
};

/// "Geminids 2026": one patch per shower per year.
Badge seasonPatch(String code, int year, {DateTime? earnedAt, DateTime? season}) {
  final name = showerNames[code] ?? 'Meteor shower';
  return Badge(
    'season-$code-$year',
    '$name $year',
    'Catch the $name on their best nights in $year. Only this once: next year is a new patch.',
    art: BadgeArt.meteor,
    steps: earnedAt == null ? const [] : [earnedAt],
    season: season,
  );
}
