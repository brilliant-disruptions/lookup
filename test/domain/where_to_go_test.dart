import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/plan/where_to_go.dart';
import 'package:lookup/domain/sky/direction.dart';
import 'package:lookup/domain/sky/visibility.dart';
import 'package:lookup/domain/weather/cloud_forecast.dart';

void main() {
  // A night from 7 PM to 6 AM (UTC, for simplicity).
  final dusk = DateTime.utc(2026, 10, 20, 19);
  final dawn = DateTime.utc(2026, 10, 21, 6);

  /// [cover] per hour from dusk; null means no forecast reaches the night.
  NightOutlook night(List<int>? cover) => NightOutlook.from(
        start: dusk,
        end: dawn,
        weather: cover == null
            ? null
            : CloudForecast(latitude: 0, longitude: 0, fetchedAt: dusk, hourly: [
                for (final (i, c) in cover.indexed) CloudSample(time: dusk.add(Duration(hours: i)), coverPercent: c),
              ]),
      );

  final clear = List.filled(11, 0);
  final overcast = List.filled(11, 100);
  // Clear until 11 PM, then cloud.
  final cloudsAt11 = [0, 0, 0, 0, ...List.filled(7, 100)];

  PlaceNight place(String name, List<int>? cover,
          {bool here = false, SkyDarkness sky = SkyDarkness.suburbs, double? km}) =>
      PlaceNight(name: name, here: here, darkness: sky, outlook: night(cover), distanceKm: km);

  test('clear hours are the longest clear spell, never guessed without a forecast', () {
    expect(place('a', clear).clearHours, 11);
    expect(place('a', cloudsAt11).clearHours, 4);
    expect(place('a', overcast).clearHours, 0);
    expect(place('a', null).clearHours, 0);
  });

  test('a clear dark sky beats a clear city sky', () {
    final ranked = rankPlaces([place('city', clear, sky: SkyDarkness.city), place('cabin', clear, sky: SkyDarkness.dark)]);
    expect(ranked.map((p) => p.name), ['cabin', 'city']);
  });

  test('a trip is suggested only when it is clearly better', () {
    final r = whereToGo([
      place('home', clear, here: true),
      // Same clear hours, one notch darker: 11 × (1.0 − 0.8) = 2.2 effective hours. Worth it.
      place('cabin', clear, sky: SkyDarkness.dark, km: 200),
    ]);
    expect(r.kind, WhereToGoKind.go);
    expect(r.best!.name, 'cabin');

    final close = whereToGo([
      place('home', [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 100], here: true),
      place('lake', clear, km: 40),
    ]);
    expect(close.kind, WhereToGoKind.stayPut);
    expect(close.best!.name, 'home');
  });

  test('go when home clouds over and a saved place stays clear', () {
    final r = whereToGo([place('home', cloudsAt11, here: true), place('cabin', clear, km: 240)]);
    expect(r.kind, WhereToGoKind.go);
    expect(r.best!.name, 'cabin');
    expect(r.ranked.first.name, 'cabin');
  });

  test('never recommends a trip into cloud: cloudy everywhere says so', () {
    final r = whereToGo([place('home', overcast, here: true), place('cabin', overcast, sky: SkyDarkness.dark)]);
    expect(r.kind, WhereToGoKind.cloudyEverywhere);
    expect(r.best, isNull);
  });

  test('a place without a forecast is never picked over one that is clear', () {
    final r = whereToGo([place('home', cloudsAt11, here: true), place('far', null, sky: SkyDarkness.dark)]);
    expect(r.kind, WhereToGoKind.stayPut);
    expect(r.ranked.last.name, 'far');
  });

  test('cloudy here and a short gap elsewhere: still worth knowing, never "stay put" under cloud', () {
    final r = whereToGo([place('home', overcast, here: true), place('lake', [100, 0, 100, 100, 100, 100, 100, 100, 100, 100, 100], km: 40)]);
    expect(r.kind, WhereToGoKind.go);
    expect(r.best!.name, 'lake');
  });

  test('no forecast anywhere: no recommendation', () {
    final r = whereToGo([place('home', null, here: true), place('cabin', null)]);
    expect(r.kind, WhereToGoKind.noForecast);
    expect(r.best, isNull);
  });

  test('without a location, the best saved place is the pick', () {
    final r = whereToGo([place('a', cloudsAt11), place('b', clear)]);
    expect(r.kind, WhereToGoKind.go);
    expect(r.best!.name, 'b');
  });

  test('ties go to here, then the nearest', () {
    final ranked = rankPlaces([place('far', clear, km: 300), place('near', clear, km: 30), place('home', clear, here: true)]);
    expect(ranked.map((p) => p.name), ['home', 'near', 'far']);
  });

  test('distance and bearing: Nashville to the Smokies is about 300 km east', () {
    const nash = (36.17, -86.78), smokies = (35.61, -83.49);
    expect(distanceKm(nash.$1, nash.$2, smokies.$1, smokies.$2), closeTo(302, 5));
    expect(compassWord(bearingDeg(nash.$1, nash.$2, smokies.$1, smokies.$2)), 'east');
    expect(bearingDeg(0, 0, 1, 0), closeTo(0, 1e-9));
    expect(bearingDeg(0, 0, 0, -1), closeTo(270, 1e-9));
  });
}
