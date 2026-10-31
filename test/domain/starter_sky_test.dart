import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/log/catch_moment.dart';
import 'package:lookup/domain/log/sighting.dart';
import 'package:lookup/domain/log/sky_log.dart';
import 'package:lookup/domain/log/starter_sky.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/plan/night_plan.dart';
import 'package:lookup/domain/sky/astro.dart';
import 'package:lookup/domain/sky/catalog.dart';
import 'package:lookup/domain/sky/tonight.dart';
import 'package:lookup/domain/sky/visibility.dart';

final now = DateTime.utc(2026, 10, 21, 20);

SkyEvent ev(String id, SkyEventType type, Duration fromNow) => SkyEvent(
  id: id,
  type: type,
  start: now.add(fromNow),
  peak: now.add(fromNow + const Duration(minutes: 2)),
  end: now.add(fromNow + const Duration(minutes: 4)),
  peakElevationDeg: 50,
  riseAzimuthDeg: 247,
  peakAzimuthDeg: 180,
  setAzimuthDeg: 100,
);

SkySighting sight(Seeability v, {int hour = 2}) => SkySighting(
  best: now.add(Duration(hours: hour)),
  altDeg: 40,
  azDeg: 200,
  verdict: v,
);

const orion = Constellation(id: 'Ori', name: 'Orion', rank: 1, centerRaDeg: 84, centerDecDeg: 0, lines: []);
const cassiopeia = Constellation(id: 'Cas', name: 'Cassiopeia', rank: 1, centerRaDeg: 15, centerDecDeg: 60, lines: []);

NightPlan night({
  List<PlanetTonight> planets = const [],
  List<ConstellationTonight> constellations = const [],
  List<ShowpieceTonight> showpieces = const [],
}) => NightPlan(
  window: null,
  outlook: null,
  planets: planets,
  moon: const MoonTonight(phase: MoonPhase.newMoon, illumination: 0, waxing: true),
  constellations: constellations,
  showpieces: showpieces,
  darkness: SkyDarkness.suburbs,
);

PlanetTonight planet(Planet p, double mag, Seeability v, {String? whyNot}) =>
    PlanetTonight(planet: p, magnitude: mag, elongationDeg: 90, evening: true, sighting: sight(v), whyNot: whyNot);

Sighting s(String id, int day, {SkyEventType? type}) => Sighting(eventId: id, seen: true, at: DateTime.utc(2026, 10, day, 20), type: type);

void main() {
  group('plan', () {
    test('a brand-new user gets a pass, the brightest easy planet and a famous pattern', () {
      final steps = StarterSky.plan(
        log: SkyLog.from(const []),
        events: [
          ev('starlink:1', SkyEventType.starlinkTrain, const Duration(hours: 5)), // Plus-only: not for free
          ev('iss:1', SkyEventType.iss, const Duration(days: 1)),
        ],
        nights: [
          night(
            planets: [planet(Planet.saturn, 0.6, Seeability.great), planet(Planet.jupiter, -2.5, Seeability.good)],
            constellations: [ConstellationTonight(orion, sight(Seeability.great))],
          ),
        ],
        now: now,
        isPlus: false,
      )!;
      expect([for (final x in steps) x.kind], StarterKind.values);
      expect(steps[0].event?.id, 'iss:1');
      expect(steps[1].skyId, 'planet:jupiter'); // brighter wins
      expect(steps[1].night, 0);
      expect(steps[2].skyId, 'con:Ori');
      expect(steps.any((x) => x.done), isFalse);
    });

    test('Plus counts the Starlink train as the pass', () {
      final steps = StarterSky.plan(
        log: SkyLog.from(const []),
        events: [
          ev('starlink:1', SkyEventType.starlinkTrain, const Duration(hours: 5)),
          ev('iss:1', SkyEventType.iss, const Duration(days: 1)),
        ],
        nights: const [],
        now: now,
        isPlus: true,
      )!;
      expect(steps[0].event?.id, 'starlink:1');
    });

    test('never picks a planet or pattern through cloud, moonlight or low on the horizon', () {
      final steps = StarterSky.plan(
        log: SkyLog.from(const []),
        events: const [],
        nights: [
          night(
            planets: [
              planet(Planet.venus, -4, Seeability.cloudy),
              planet(Planet.jupiter, -2.5, Seeability.low),
              planet(Planet.mars, 0, Seeability.patchy),
              planet(Planet.saturn, 0.6, Seeability.great, whyNot: 'Too close to the Sun'),
            ],
            constellations: [ConstellationTonight(orion, sight(Seeability.moonlit))],
            showpieces: [ShowpieceTonight(showpieces.firstWhere((x) => x.id == 'm45'), sight(Seeability.patchy))],
          ),
          night(
            planets: [planet(Planet.jupiter, -2.5, Seeability.good)],
            constellations: [ConstellationTonight(cassiopeia, sight(Seeability.good))],
          ),
        ],
        now: now,
        isPlus: false,
      )!;
      expect(steps[0].waiting, isTrue); // no pass in the fortnight
      expect((steps[1].skyId, steps[1].night), ('planet:jupiter', 1));
      expect((steps[2].skyId, steps[2].night), ('con:Cas', 1));
    });

    test('falls back to a naked-eye showpiece, never a binocular one', () {
      final m45 = showpieces.firstWhere((x) => x.id == 'm45');
      final binoculars = showpieces.firstWhere((x) => x.aid == Aid.binoculars);
      final steps = StarterSky.plan(
        log: SkyLog.from(const []),
        events: const [],
        nights: [
          night(showpieces: [ShowpieceTonight(binoculars, sight(Seeability.great)), ShowpieceTonight(m45, sight(Seeability.good))]),
        ],
        now: now,
        isPlus: false,
      )!;
      expect(steps[2].skyId, 'm45');
    });

    test('ticks what is done from the log, and disappears when all three are', () {
      final some = SkyLog.from([s('iss:a', 10), s('obj:planet:saturn', 11, type: SkyEventType.skyObject)]);
      final steps = StarterSky.plan(log: some, events: const [], nights: const [], now: now, isPlus: false)!;
      expect([for (final x in steps) x.done], [true, true, false]);

      final all = SkyLog.from([s('iss:a', 10), s('obj:planet:saturn', 11), s('obj:m45', 12)]);
      expect(StarterSky.plan(log: all, events: const [], nights: const [], now: now, isPlus: false), isNull);
    });

    test('the Moon does not count as a star pattern', () {
      final log = SkyLog.from([s('obj:moon', 10)]);
      expect(StarterSky.progress(log.seen).stars, isFalse);
    });

    test('seasoned users never see it', () {
      final log = SkyLog.from([for (var d = 1; d <= 10; d++) s('iss:$d', d)]);
      expect(StarterSky.plan(log: log, events: const [], nights: const [], now: now, isPlus: false), isNull);
    });
  });

  group('completedBy', () {
    test('true only for the sighting that finished all three', () {
      final log = SkyLog.from([s('iss:a', 10), s('obj:planet:saturn', 11), s('obj:con:Ori', 12), s('iss:b', 13)]);
      expect(StarterSky.completedBy(log, 'obj:con:Ori'), isTrue);
      expect(StarterSky.completedBy(log, 'iss:b'), isFalse); // a second pass adds nothing
      expect(StarterSky.completedBy(log, 'iss:a'), isFalse); // it came first; the pattern finished it
      expect(StarterSky.completedBy(log, 'nope'), isFalse);
    });

    test('the "You caught it" moment knows it', () {
      final log = SkyLog.from([s('iss:a', 10), s('obj:planet:saturn', 11), s('obj:m45', 12)]);
      final m = CatchMoment.of(log: log, eventId: 'obj:m45', upcoming: const [], now: now, isPlus: false)!;
      expect(m.completesStarter, isTrue);
      final first = CatchMoment.of(log: log, eventId: 'iss:a', upcoming: const [], now: now, isPlus: false)!;
      expect(first.completesStarter, isFalse);
    });
  });
}
