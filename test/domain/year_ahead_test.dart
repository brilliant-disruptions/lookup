import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/events/year_ahead.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/sky/seasons.dart';

void main() {
  // Denver, from 25 Nov 2026.
  final now = DateTime.utc(2026, 11, 25, 18);
  final sw = Stopwatch()..start();
  final year = yearAhead(now: now, latDeg: 39.74, lonDeg: -104.99);
  sw.stop();

  test('in order, inside the year, and quick enough to build on opening', () {
    for (var i = 1; i < year.length; i++) {
      expect(year[i].at.isBefore(year[i - 1].at), isFalse);
    }
    expect(year.first.at.isBefore(now.subtract(const Duration(days: 1))), isFalse);
    expect(year.last.at.isAfter(now.add(const Duration(days: yearAheadDays + 1))), isFalse);
    expect(sw.elapsed, lessThan(const Duration(seconds: 3)));
  });

  test('all four seasons, twelve or thirteen full Moons, the next supermoon named', () {
    expect(year.where((x) => x.season != null).length, 4);
    final fulls = year.where((x) => x.event?.type == SkyEventType.fullMoonRise).map((x) => x.event!).toList();
    expect(fulls.length, inInclusiveRange(12, 13));
    expect(fulls.first.details['supermoon'], isTrue, reason: '24 Dec 2026');
    expect(year.firstWhere((x) => x.season != null).season!.mark, SeasonMark.decemberSolstice);
  });

  test('the big meteor showers are there', () {
    final names = year.where((x) => x.event?.type == SkyEventType.meteorShower).map((x) => x.event!.details['shower']).toSet();
    expect(names, containsAll(['Geminids', 'Perseids']));
  });
}
