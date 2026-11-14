import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/aurora/aurora_rules.dart';
import 'package:lookup/domain/aurora/seen_nearby.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/plan/where_to_go.dart' show distanceKm;

// Edinburgh on a November night: dark by 18:00 UTC.
const _lat = 55.95, _lon = -3.19;
final _now = DateTime.utc(2026, 11, 2, 22);

AuroraReport _r(String who, double lat, double lon, {int minsAgo = 3, SeenHow how = SeenHow.eye}) {
  final c = reportCell(lat, lon);
  return AuroraReport(cellLat: c.lat, cellLon: c.lon, at: _now.subtract(Duration(minutes: minsAgo)), how: how, reporter: who);
}

// Around the Firth of Forth and the Borders: within 100 km, a little south.
final _crowd = [
  _r('a', 55.86, -4.25), // Glasgow
  _r('b', 56.40, -3.43), // Perth
  _r('c', 55.60, -2.73, how: SeenHow.camera), // the Borders
  _r('d', 56.12, -3.16, minsAgo: 1), // Fife
  _r('e', 55.86, -4.25, minsAgo: 12), // Glasgow again, someone else
];

CrowdVerdict _check(List<AuroraReport> reports, {double kp = 5, int ovation = 40, int? clouds = 10, DateTime? now}) => crowdConfirms(
      reports: reports,
      now: now ?? _now,
      latDeg: _lat,
      lonDeg: _lon,
      estimatedKp: kp,
      ovationProbability: ovation,
      cloudCoverPercent: clouds,
    );

void main() {
  test('reports are filed under a half-degree cell, never a position', () {
    final c = reportCell(55.9533, -3.1883);
    expect(c.lat, 55.75);
    expect(c.lon, -3.25);
    expect(reportCell(55.99, -3.01), c);
    expect(distanceKm(55.9533, -3.1883, c.lat, c.lon), lessThan(40));
    // Wraps the date line, keeps off the poles.
    expect(reportCell(10, 181).lon, reportCell(10, -179).lon);
    expect(reportCell(90, 0).lat, lessThan(90));
  });

  test('enough people nearby, a plausible Kp, dark and clear: tell them, in words', () {
    final v = _check(_crowd);
    expect(v.confirmed, isTrue, reason: v.reason);
    expect(v.people, 5);
    expect(v.byEye, 4);
    expect(v.headline, startsWith('Aurora being seen'));
    expect(v.headline, isNot(contains('°')));
    // In the reader's units: km by default, miles when they read miles.
    expect(v.nearestKm, greaterThanOrEqualTo(30), reason: 'the crowd is a little way off');
    expect(v.headline, contains(' km '));
    expect(v.headlineIn(miles: true), contains(' miles '));
    expect(v.body(const CrowdRules().window), contains('5 people'));
  });

  test('reports never alert where the model alone wouldn\'t: anyone can post them', () {
    final needed = kpNeededAt(_lat, _lon);
    expect(_check(_crowd, kp: needed - 0.5).confirmed, isTrue, reason: 'the model says go: the crowd says where');
    // A little short for the model is no longer the crowd's to call...
    final short = _check(_crowd, kp: needed - 1.4);
    expect(short.confirmed, isFalse);
    expect(short.reason, contains('Kp'));
    expect(_check(_crowd, kp: needed - 2).reason, contains('Kp'));
    // ...and nor is a quiet Ovation, however many say they can see it.
    final quiet = _check(_crowd, ovation: 5);
    expect(quiet.confirmed, isFalse);
    expect(quiet.reason, contains('ovation'));
  });

  test('a made-up crowd (fresh tokens, two cells near a city) can\'t raise an alert the model wouldn\'t', () {
    // The finding's attack: four self-chosen reporter tokens split across two
    // adjacent cells by Edinburgh, Kp within 1.5 of what's needed, dark and
    // clear. The relay counts them as four people; the phone mustn't alert.
    final forged = [
      for (var i = 0; i < 4; i++) _r('made-up-token-$i-xxxxxxxx', 55.80, i.isEven ? -3.30 : -2.80, minsAgo: 1),
    ];
    final needed = kpNeededAt(_lat, _lon);
    for (final kp in [needed - 1.5, needed - 1.2, needed - 0.5, needed + 2]) {
      for (final ovation in [0, 5, 19]) {
        expect(_check(forged, kp: kp, ovation: ovation).confirmed, isFalse, reason: 'Kp $kp, Ovation $ovation%');
      }
    }
    expect(_check(forged, kp: needed - 1.2, ovation: 80).confirmed, isFalse, reason: 'Kp a little short');
  });

  test('whatever the reports, the crowd confirms only when the model alone would alert', () {
    // Kp, Ovation, cloud and time of day across the gates; the full crowd every time.
    final noon = DateTime.utc(2026, 11, 2, 12);
    for (final at in [_now, noon]) {
      final reports = [
        for (final r in _crowd) AuroraReport(cellLat: r.cellLat, cellLon: r.cellLon, at: at.subtract(_now.difference(r.at)), how: r.how, reporter: r.reporter),
      ];
      for (var kp = 0.0; kp <= 9; kp += 0.25) {
        for (final ovation in [0, 5, 19, 20, 40, 80]) {
          for (final clouds in <int?>[null, 0, 30, 60, 61, 90]) {
            final crowd = crowdConfirms(
                reports: reports, now: at, latDeg: _lat, lonDeg: _lon, estimatedKp: kp, ovationProbability: ovation, cloudCoverPercent: clouds);
            final model = auroraNow(
                now: at, latDeg: _lat, lonDeg: _lon, estimatedKp: kp, ovationProbability: ovation, cloudCoverPercent: clouds);
            if (crowd.confirmed) expect(model.alert, isTrue, reason: '$at Kp $kp, Ovation $ovation%, cloud $clouds%');
            if (model.alert) expect(crowd.confirmed, isTrue, reason: 'a real crowd still words it: $at Kp $kp, Ovation $ovation%, cloud $clouds%');
          }
        }
      }
    }
  });

  test('never through cloud, never in daylight', () {
    expect(_check(_crowd, clouds: 85).reason, contains('cloudy'));
    // Midday: it isn't dark, whatever people say.
    final noon = DateTime.utc(2026, 11, 2, 12);
    final day = [for (final r in _crowd) AuroraReport(cellLat: r.cellLat, cellLon: r.cellLon, at: noon, how: r.how, reporter: r.reporter)];
    expect(_check(day, now: noon).reason, 'not dark');
  });

  test('one person pressing the button over and over is one person', () {
    final spam = [for (var i = 0; i < 20; i++) _r('same', 55.86, -4.25, minsAgo: i % 15)];
    final v = _check(spam);
    expect(v.confirmed, isFalse);
    expect(v.reason, contains('1 people'));
  });

  test('a crowd all in one place isn\'t enough on its own', () {
    final party = [for (var i = 0; i < 8; i++) _r('p$i', 55.86, -4.25)];
    expect(_check(party).reason, 'all from one place');
  });

  test('old news: nothing in the last ten minutes, or all past the window', () {
    final stale = [for (final r in _crowd) _r(r.reporter, r.cellLat, r.cellLon, minsAgo: 14)];
    expect(_check(stale).reason, 'no recent reports');
    final ancient = [for (final r in _crowd) _r(r.reporter, r.cellLat, r.cellLon, minsAgo: 45)];
    expect(_check(ancient).confirmed, isFalse);
  });

  test('far away or much nearer the pole doesn\'t count for your sky', () {
    // London hears from Scotland: too far, and the aurora is easier up there.
    final v = crowdConfirms(
        reports: _crowd, now: _now, latDeg: 51.5, lonDeg: -0.12, estimatedKp: 7, ovationProbability: 40, cloudCoverPercent: 0);
    expect(v.confirmed, isFalse);
    // Even with a huge radius, reports from well toward the pole are left out.
    final wide = crowdConfirms(
        reports: _crowd, now: _now, latDeg: 51.5, lonDeg: -0.12, estimatedKp: 7, ovationProbability: 40, cloudCoverPercent: 0,
        rules: const CrowdRules(radiusKm: 800));
    expect(wide.confirmed, isFalse);
    expect(wide.reason, contains('0 people'));
  });

  test('reports from the future (clock skew) aren\'t counted', () {
    final future = [for (final r in _crowd) _r(r.reporter, r.cellLat, r.cellLon, minsAgo: -5)];
    expect(_check(future).confirmed, isFalse);
  });

  test('the cells to ask the relay about cover the radius and nothing far', () {
    final cells = cellsNear(_lat, _lon);
    expect(cells, contains(reportCell(_lat, _lon)));
    expect(cells, contains(reportCell(55.86, -4.25)));
    for (final c in cells) {
      expect(distanceKm(_lat, _lon, c.lat, c.lon), lessThan(300));
    }
  });

  test('reports survive the trip to the relay and back', () {
    final r = _crowd.first;
    final back = AuroraReport.fromJson(r.toJson());
    expect((back.cellLat, back.cellLon, back.at, back.how, back.reporter), (r.cellLat, r.cellLon, r.at, r.how, r.reporter));
  });

  test('offered where the aurora shows by Kp 6, not where it almost never does', () {
    for (final (name, lat, lon) in const [
      ('Edinburgh', 55.95, -3.19),
      ('Tromsø', 69.65, 18.96),
      ('Minneapolis', 44.98, -93.27),
      ('Anchorage', 61.22, -149.9),
      ('Dublin', 53.35, -6.26),
    ]) {
      expect(seenNearbyOffered(lat, lon), isTrue, reason: name);
    }
    for (final (name, lat, lon) in const [
      ('Madrid', 40.42, -3.70),
      ('Miami', 25.76, -80.19),
      ('Singapore', 1.35, 103.82),
      // The far south needs about Kp 6.7: not yet.
      ('Dunedin', -45.87, 170.5),
    ]) {
      expect(seenNearbyOffered(lat, lon), isFalse, reason: name);
    }
  });

  group('the Seen near you line on Tonight', () {
    SkyEvent auroraNow({required DateTime at, bool crowd = true}) {
      final v = _check(_crowd, now: at);
      return SkyEvent(
        id: 'aurora-now:x',
        type: SkyEventType.auroraNow,
        start: at,
        peak: at,
        end: at.add(const Duration(hours: 3)),
        peakElevationDeg: 15,
        riseAzimuthDeg: 0,
        peakAzimuthDeg: 0,
        setAzimuthDeg: 0,
        details: {
          'kp': 5.0,
          if (crowd) ...{'crowd': true, 'people': v.people, 'headline': v.headline, 'body': v.body(const CrowdRules().window)},
        },
      );
    }

    test('shows the crowd\'s words while the count it quotes is current', () {
      final e = auroraNow(at: _now);
      final line = seenNearYouLine([e], _now.add(const Duration(minutes: 5)), relayConfigured: true);
      expect(line, same(e));
      expect(line!.details['headline'], startsWith('Aurora being seen'));
    });

    test('goes once "in the last 20 minutes" is no longer true, though the alert window runs on', () {
      // The event lasts 3 h for the alert's sake; the line mustn't, or it
      // would quote an old crowd as if it were looking now.
      final e = auroraNow(at: _now);
      final window = const CrowdRules().window;
      expect(seenNearYouLine([e], _now.add(window), relayConfigured: true), same(e));
      expect(seenNearYouLine([e], _now.add(window + const Duration(minutes: 1)), relayConfigured: true), isNull);
    });

    test('never from the Kp model alone: an aurora-now with no crowd behind it keeps the outlook card', () {
      expect(seenNearYouLine([auroraNow(at: _now, crowd: false)], _now, relayConfigured: true), isNull);
    });

    test('hidden in a build without the relay', () {
      expect(seenNearYouLine([auroraNow(at: _now)], _now, relayConfigured: false), isNull);
    });
  });
}
