import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/aurora/aurora_rules.dart';
import 'package:lookup/domain/aurora/seen_nearby.dart';
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

CrowdVerdict _check(List<AuroraReport> reports, {double kp = 5, int? clouds = 10, DateTime? now}) => crowdConfirms(
      reports: reports,
      now: now ?? _now,
      latDeg: _lat,
      lonDeg: _lon,
      estimatedKp: kp,
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
    expect(v.body(const CrowdRules().window), contains('5 people'));
  });

  test('reports alone never do it: the Kp model has to find it plausible here', () {
    final needed = kpNeededAt(_lat, _lon);
    expect(_check(_crowd, kp: needed - 1.4).confirmed, isTrue, reason: 'a little short is the crowd\'s to call');
    final v = _check(_crowd, kp: needed - 2);
    expect(v.confirmed, isFalse);
    expect(v.reason, contains('Kp'));
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
    final v = crowdConfirms(reports: _crowd, now: _now, latDeg: 51.5, lonDeg: -0.12, estimatedKp: 7, cloudCoverPercent: 0);
    expect(v.confirmed, isFalse);
    // Even with a huge radius, reports from well toward the pole are left out.
    final wide = crowdConfirms(
        reports: _crowd, now: _now, latDeg: 51.5, lonDeg: -0.12, estimatedKp: 7, cloudCoverPercent: 0,
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
}
