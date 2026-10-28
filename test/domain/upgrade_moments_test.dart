import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/plus/upgrade_moments.dart';

void main() {
  final now = DateTime.utc(2026, 10, 28, 3);
  final day1 = LookUpSettings(firstOpenedAt: now.subtract(const Duration(hours: 5)));

  test('not on someone just starting out', () {
    expect(offerPlusAfterSighting(day1, seenCount: 1, now: now), isFalse);
  });

  test('yes once they are really using it: a couple of sightings, or a week in', () {
    expect(offerPlusAfterSighting(day1, seenCount: 2, now: now), isTrue);
    final weekIn = LookUpSettings(firstOpenedAt: now.subtract(const Duration(days: 8)));
    expect(offerPlusAfterSighting(weekIn, seenCount: 1, now: now), isTrue);
  });

  test('at most weekly, never with LookUp+ and never under red light', () {
    expect(offerPlusAfterSighting(day1.copyWith(lastPlusAskAt: now.subtract(const Duration(days: 3))), seenCount: 5, now: now),
        isFalse);
    expect(offerPlusAfterSighting(day1.copyWith(lastPlusAskAt: now.subtract(const Duration(days: 8))), seenCount: 5, now: now),
        isTrue);
    expect(offerPlusAfterSighting(day1.copyWith(isPlus: true), seenCount: 5, now: now), isFalse);
    expect(offerPlusAfterSighting(day1.copyWith(nightVision: true), seenCount: 5, now: now), isFalse);
  });

  test('the ask dates survive a restart', () {
    final s = day1.copyWith(lastPlusAskAt: now);
    final back = LookUpSettings.fromJson(s.toJson());
    expect(back.firstOpenedAt, day1.firstOpenedAt);
    expect(back.lastPlusAskAt, now);
    expect(LookUpSettings.fromJson(const {}).lastPlusAskAt, isNull);
  });
}
