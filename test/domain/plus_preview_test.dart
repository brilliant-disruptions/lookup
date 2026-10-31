import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/plus/plus_preview.dart';

final now = DateTime.utc(2026, 11, 6, 22);

SkyEvent ev(String id, SkyEventType type, Duration fromNow, {Map<String, Object?> details = const {}}) => SkyEvent(
  id: id,
  type: type,
  start: now.add(fromNow),
  peak: now.add(fromNow + const Duration(minutes: 2)),
  end: now.add(fromNow + const Duration(minutes: 4)),
  peakElevationDeg: 50,
  riseAzimuthDeg: 247,
  peakAzimuthDeg: 180,
  setAzimuthDeg: 95,
  details: details,
);

void main() {
  test('the next Plus-only taps in the coming weeks, soonest first, three at most', () {
    final p = PlusPreview.of([
      ev('iss:1', SkyEventType.iss, const Duration(days: 1)), // free: not shown
      ev('launch:1', SkyEventType.rocketLaunch, const Duration(days: 9)),
      ev('starlink:1', SkyEventType.starlinkTrain, const Duration(days: 2)),
      ev('tiangong:1', SkyEventType.tiangong, const Duration(days: 4)),
      ev('tiangong:2', SkyEventType.tiangong, const Duration(days: 6)),
      ev('starlink:far', SkyEventType.starlinkTrain, const Duration(days: 40)), // beyond the window
      ev('starlink:past', SkyEventType.starlinkTrain, const Duration(days: -1)),
      ev('outlook:1', SkyEventType.auroraOutlook, const Duration(hours: 5)), // never pushed
    ], now);
    expect([for (final e in p.soonest) e.id], ['starlink:1', 'tiangong:1', 'tiangong:2']);
    expect(p.count, 4);
  });

  test('shown to free users unless they said not now this week; never to Plus', () {
    expect(PlusPreview.show(isPlus: false, snoozedUntil: null, now: now), isTrue);
    expect(PlusPreview.show(isPlus: true, snoozedUntil: null, now: now), isFalse);
    expect(PlusPreview.show(isPlus: false, snoozedUntil: now.add(const Duration(days: 3)), now: now), isFalse);
    expect(PlusPreview.show(isPlus: false, snoozedUntil: now.subtract(const Duration(minutes: 1)), now: now), isTrue);
  });

  test('the snooze survives a restart', () {
    final until = now.add(PlusPreview.snooze);
    final s = LookUpSettings.fromJson(LookUpSettings(plusCardSnoozedUntil: until).toJson());
    expect(s.plusCardSnoozedUntil, until);
    expect(LookUpSettings.fromJson(const {}).plusCardSnoozedUntil, isNull);
  });
}
