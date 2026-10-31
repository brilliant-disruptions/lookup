import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/events/solar_eclipses.dart';
import 'package:lookup/domain/models/sky_event.dart';

BesselianElements on(int y, int m, int d) => besselianElements.firstWhere((e) => e.date == DateTime.utc(y, m, d));

void expectNear(DateTime got, DateTime want, {int seconds = 10}) =>
    expect(got.difference(want).inMilliseconds.abs(), lessThan(seconds * 1000), reason: 'got $got, want $want');

void main() {
  // Published local circumstances (NASA GSFC / timeanddate) for well-known spots.
  test('Dallas, 8 Apr 2024: total, 3 min 51 s from 18:40:41 UT', () {
    final l = localSolarEclipse(on(2024, 4, 8), 32.7767, -96.797)!;
    expect(l.kind, LocalEclipseKind.total);
    expectNear(l.centralStart!, DateTime.utc(2024, 4, 8, 18, 40, 41));
    expect(l.centralDuration!.inSeconds, inInclusiveRange(225, 235));
    expectNear(l.greatest, DateTime.utc(2024, 4, 8, 18, 42, 36), seconds: 30);
  });

  test('Carbondale, 21 Aug 2017: total, about 2 min 40 s from 18:20 UT', () {
    final l = localSolarEclipse(on(2017, 8, 21), 37.727, -89.217)!;
    expect(l.kind, LocalEclipseKind.total);
    expectNear(l.centralStart!, DateTime.utc(2017, 8, 21, 18, 20, 0));
    expect(l.centralDuration!.inSeconds, inInclusiveRange(150, 165));
  });

  test('Nashville: total in 2017, about 95% in 2024 and never called total', () {
    expect(localSolarEclipse(on(2017, 8, 21), 36.1627, -86.7816)!.kind, LocalEclipseKind.total);
    final l = localSolarEclipse(on(2024, 4, 8), 36.1627, -86.7816)!;
    expect(l.kind, LocalEclipseKind.partial);
    expect(l.obscuration, closeTo(0.947, 0.01));
    expectNear(l.greatest, DateTime.utc(2024, 4, 8, 19, 3, 0), seconds: 60);
  });

  test('New York, 2024: about 90% covered', () {
    expect(localSolarEclipse(on(2024, 4, 8), 40.7128, -74.006)!.obscuration, closeTo(0.896, 0.01));
  });

  test('2 Aug 2027: over six minutes at Luxor; partial in Madrid and London', () {
    final luxor = localSolarEclipse(on(2027, 8, 2), 25.6872, 32.6396)!;
    expect(luxor.kind, LocalEclipseKind.total);
    expect(luxor.centralDuration!.inSeconds, inInclusiveRange(370, 385));
    expect(localSolarEclipse(on(2027, 8, 2), 40.4168, -3.7038)!.kind, LocalEclipseKind.partial);
    expect(localSolarEclipse(on(2027, 8, 2), 51.5, -0.12)!.obscuration, closeTo(0.42, 0.03));
  });

  test('nothing for places on the night side', () {
    expect(localSolarEclipse(on(2024, 4, 8), 35.68, 139.69), isNull); // Tokyo
  });

  test('right at the edge of the path it says "near the path", never total', () {
    // Walk south from Dallas (deep in the 2024 path) until totality is no
    // longer promised: the next step out must be near-path, not partial.
    final e = on(2024, 4, 8);
    var lat = 32.78;
    LocalEclipseKind kind = LocalEclipseKind.total;
    while (kind == LocalEclipseKind.total) {
      lat -= 0.01;
      kind = localSolarEclipse(e, lat, -96.797)!.kind;
    }
    expect(kind, LocalEclipseKind.nearPath);
  });

  test('events: only eclipses worth stepping out for, in the window, free and pushed', () {
    // Nashville in the weeks before 2024's eclipse.
    final events = solarEclipseEvents(now: DateTime.utc(2024, 3, 20), latDeg: 36.1627, lonDeg: -86.7816);
    expect(events, hasLength(1));
    final e = events.single;
    expect(e.type, SkyEventType.solarEclipse);
    expect(e.type.pushes, isTrue);
    expect(e.plusOnly, isFalse);
    expect(solarEclipseHeadline(e), '94% of the Sun covered');
    // Dallas gets the totality headline.
    final dallas = solarEclipseEvents(now: DateTime.utc(2024, 3, 20), latDeg: 32.7767, lonDeg: -96.797).single;
    expect(solarEclipseHeadline(dallas), startsWith('Total eclipse here: 3 min'));
    // Out of the window, nothing.
    expect(solarEclipseEvents(now: DateTime.utc(2024, 1, 1), latDeg: 36.1627, lonDeg: -86.7816), isEmpty);
  });

  test('obscuration: nothing, all, and an annular ring', () {
    expect(obscurationFor(0, 1.0), 0);
    expect(obscurationFor(1.02, 1.03), 1);
    expect(obscurationFor(0.97, 0.94), closeTo(0.94 * 0.94, 1e-9));
    expect(obscurationFor(0.5, 1.0), inExclusiveRange(0.35, 0.45));
  });
}
