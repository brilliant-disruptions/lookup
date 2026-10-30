import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/plan/night_plan.dart';
import 'package:lookup/domain/plan/tonight_story.dart';
import 'package:lookup/domain/sky/astro.dart';
import 'package:lookup/domain/sky/tonight.dart';
import 'package:lookup/domain/sky/visibility.dart';

void main() {
  final now = DateTime.utc(2026, 10, 30, 21); // 4 PM CDT
  final dark = (start: DateTime.utc(2026, 10, 30, 23, 40), end: DateTime.utc(2026, 10, 31, 11, 20));

  SkyEvent ev(String id, SkyEventType type, DateTime start) => SkyEvent(
        id: id,
        type: type,
        start: start,
        peak: start.add(const Duration(minutes: 2)),
        end: start.add(const Duration(minutes: 5)),
        peakElevationDeg: 50,
        riseAzimuthDeg: 250,
        peakAzimuthDeg: 180,
        setAzimuthDeg: 100,
      );

  SkySighting seen(Seeability v) => SkySighting(best: DateTime.utc(2026, 10, 31, 3), altDeg: 40, azDeg: 150, verdict: v);

  NightPlan plan({Seeability planets = Seeability.great, Seeability moon = Seeability.good, double lit = 0.6}) => NightPlan(
        window: dark,
        outlook: null,
        planets: [
          PlanetTonight(planet: Planet.saturn, magnitude: 0.6, elongationDeg: 150, evening: true, sighting: seen(planets)),
          PlanetTonight(planet: Planet.jupiter, magnitude: -2.5, elongationDeg: 100, evening: false, sighting: seen(planets)),
          PlanetTonight(planet: Planet.mars, magnitude: 1.1, elongationDeg: 60, evening: false, sighting: seen(planets)),
          const PlanetTonight(planet: Planet.venus, magnitude: -3.9, elongationDeg: 5, evening: true, whyNot: 'Too close to the Sun'),
        ],
        moon: MoonTonight(phase: MoonPhase.waxingGibbous, illumination: lit, waxing: true, sighting: seen(moon)),
        constellations: const [],
        showpieces: const [],
        darkness: SkyDarkness.suburbs,
      );

  final iss = ev('iss:a', SkyEventType.iss, DateTime.utc(2026, 10, 31, 0, 10));
  final train = ev('starlink:a', SkyEventType.starlinkTrain, DateTime.utc(2026, 10, 31, 1, 30));
  final transit = ev('transit-moon:a', SkyEventType.issTransit, DateTime.utc(2026, 10, 31, 2));
  final later = ev('tiangong:a', SkyEventType.tiangong, DateTime.utc(2026, 11, 3, 0, 30));

  test('free: clouds, tonight in order, the brightest planets, the Moon, then the real next Plus sight', () {
    final f = tonightStory(plan: plan(), events: [later, train, transit, iss], now: now, isPlus: false);
    expect(f.first, isA<OpeningFrame>());
    final events = f.whereType<EventFrame>().toList();
    expect(events.map((e) => e.event.id), ['iss:a', 'starlink:a']); // no transit, nothing after the night
    expect(events.map((e) => e.locked), [false, true]);
    expect(f.whereType<PlanetFrame>().map((p) => p.planet.planet), [Planet.jupiter, Planet.saturn]);
    expect(f.whereType<MoonFrame>(), hasLength(1));
    expect((f.last as EndFrame).upsell?.id, 'starlink:a');
  });

  test('with Plus nothing is locked and nothing is sold', () {
    final f = tonightStory(plan: plan(), events: [train, iss, later], now: now, isPlus: true);
    expect(f.whereType<EventFrame>().every((e) => !e.locked), isTrue);
    expect((f.last as EndFrame).upsell, isNull);
  });

  test('free with nothing Plus-only tonight: the end frame names the next one ahead', () {
    final f = tonightStory(plan: plan(), events: [iss, later], now: now, isPlus: false);
    expect((f.last as EndFrame).upsell?.id, 'tiangong:a');
    expect((tonightStory(plan: plan(), events: [iss], now: now, isPlus: false).last as EndFrame).upsell, isNull);
  });

  test('never through cloud: no planet or Moon frames under a cloudy sky, nor a sliver of Moon', () {
    final cloudy = tonightStory(plan: plan(planets: Seeability.cloudy, moon: Seeability.cloudy), events: [iss], now: now, isPlus: false);
    expect(cloudy.whereType<PlanetFrame>(), isEmpty);
    expect(cloudy.whereType<MoonFrame>(), isEmpty);
    expect(tonightStory(plan: plan(lit: 0.03), events: const [], now: now, isPlus: false).whereType<MoonFrame>(), isEmpty);
  });

  test('without a plan it still opens and ends', () {
    final f = tonightStory(plan: null, events: [iss], now: now, isPlus: false);
    expect(f.first, isA<OpeningFrame>());
    expect(f.whereType<EventFrame>(), hasLength(1));
    expect(f.last, isA<EndFrame>());
  });
}
