import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/log/restore.dart';
import 'package:lookup/domain/log/sky_log.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/photo/catch_tag.dart';

final _png = Uint8List.fromList(const [
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 2, 0, 0, 0, 1, 8, 2, 0, 0, 0, 123, 64, 232, 221, //
  0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 248, 207, 0, 4, 255, 1, 7, 0, 1, 255, 226, 35, 158, 89, //
  0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
]);

void main() {
  final t0 = DateTime.utc(2026, 11, 2, 23);
  CatchTag tag(String id, int day, {String type = 'iss', double? el, double? mag}) =>
      CatchTag(eventId: id, title: 'x', at: t0.add(Duration(days: day)), place: 'Nashville', type: type, elevationDeg: el, magnitude: mag);

  test('a picture carries enough to rebuild its sighting, badges included', () {
    final back = catchTagOf(pngWithCatchTag(_png, tag('iss:1', 0, el: 82, mag: -3.9)))!;
    expect((back.type, back.elevationDeg, back.magnitude), ('iss', 82.0, -3.9));
  });

  test('only sightings the Log lacks, the earliest picture of each, oldest first', () {
    final found = [
      (assetId: 'a', tag: tag('iss:2', 3)),
      (assetId: 'b', tag: tag('iss:1', 1, el: 82, mag: -3.9)),
      (assetId: 'c', tag: tag('iss:2', 2)), // an earlier picture of the same pass
      (assetId: 'd', tag: tag('iss:have', 0)),
    ];
    final r = restorable(found, {'iss:have'});
    expect([for (final x in r) (x.sighting.eventId, x.assetId)], [('iss:1', 'b'), ('iss:2', 'c')]);
    final s = r.first.sighting;
    expect((s.seen, s.type, s.place), (true, SkyEventType.iss, 'Nashville'));
    // The badges come back with them.
    final log = SkyLog.from([for (final x in r) x.sighting]);
    final earned = {for (final b in log.badges) if (b.earned) b.id};
    expect(earned, containsAll(['first-light', 'station-spotter', 'overhead', 'venus-bright']));
  });
}
