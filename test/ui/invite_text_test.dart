import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/ui/share_card.dart';

void main() {
  final start = DateTime.utc(2026, 11, 6, 3, 5);
  final e = SkyEvent(
    id: 'iss:1',
    type: SkyEventType.iss,
    start: start,
    peak: start.add(const Duration(minutes: 2)),
    end: start.add(const Duration(minutes: 4)),
    peakElevationDeg: 60,
    riseAzimuthDeg: 247,
    peakAzimuthDeg: 180,
    setAzimuthDeg: 95,
  );

  test('from the heads-up, the invite says it\'s minutes away', () {
    final s = inviteText(e, 'Nashville', now: start.subtract(const Duration(minutes: 10)));
    expect(s, startsWith('Step outside with me: ISS flyover over Nashville in 10 minutes'));
    expect(s, contains('Face west-southwest and look up.'));
    expect(inviteText(e, null, now: start.subtract(const Duration(seconds: 40))), contains('in under a minute'));
  });

  test('days ahead, it\'s a plan', () {
    expect(inviteText(e, null, now: start.subtract(const Duration(days: 2))), startsWith('Look up with me: ISS flyover'));
  });
}
