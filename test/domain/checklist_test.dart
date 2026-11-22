import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/log/checklist.dart';
import 'package:lookup/domain/log/sighting.dart';
import 'package:lookup/domain/models/sky_event.dart';

Sighting _s(String id, {SkyEventType? type, bool seen = true, int day = 20}) =>
    Sighting(eventId: id, seen: seen, at: DateTime.utc(2026, 10, day), type: type);

void main() {
  test('every kind of sight is listed, none ticked on an empty log', () {
    final list = skyChecklist(const []);
    expect(list.length, greaterThan(20));
    expect(list.map((i) => i.key).toSet().length, list.length, reason: 'each kind once');
    expect(list.first.key, 'moon', reason: 'the easy ones first');
    expect(list.last.key, 'solarEclipse');
    expect(list.any((i) => i.seen), isFalse);
  });

  test('a catch ticks its own kind, and only a real catch does', () {
    final list = skyChecklist([
      _s('obj:planet:saturn', type: SkyEventType.skyObject, day: 22),
      _s('obj:moon:20261020', type: SkyEventType.skyObject),
      _s('obj:moon:20261019', type: SkyEventType.skyObject, day: 19),
      _s('iss:a'), // an old answer, typed from its id
      _s('obj:con:Ori', type: SkyEventType.skyObject),
      _s('obj:m45', type: SkyEventType.skyObject),
      _s('aurora:x', type: SkyEventType.auroraOutlook),
      _s('tiangong:a', type: SkyEventType.tiangong, seen: false), // answered "missed it"
    ]);
    ChecklistItem item(String key) => list.singleWhere((i) => i.key == key);
    expect(list.where((i) => i.seen).map((i) => i.key), ['moon', 'iss', 'planet:saturn', 'constellation', 'showpiece', 'aurora']);
    expect(item('moon').count, 2);
    expect(item('moon').latest!.eventId, 'obj:moon:20261020', reason: 'newest first, as the Log keeps them');
    expect(item('planet:venus').seen, isFalse, reason: 'Saturn is not Venus');
    expect(item('tiangong').seen, isFalse, reason: 'a miss is not a catch');
  });
}
