import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/plus/free_plan.dart';

void main() {
  test('free plans tonight and the next two nights; Plus the fortnight', () {
    expect([for (var n = 0; n < 5; n++) FreePlan.canPlanNight(n, isPlus: false)], [true, true, true, false, false]);
    expect(FreePlan.canPlanNight(13, isPlus: true), isTrue);
  });

  test('free keeps one saved place; Plus as many as they like', () {
    expect(FreePlan.canAddPlace(0, isPlus: false), isTrue);
    expect(FreePlan.canAddPlace(1, isPlus: false), isFalse);
    expect(FreePlan.canAddPlace(12, isPlus: true), isTrue);
  });

  test('where to go, transits and the extra alerts are LookUp+', () {
    for (final f in [PlusFeature.whereToGo, PlusFeature.transits, PlusFeature.alerts]) {
      expect(FreePlan.canUse(f, isPlus: false), isFalse, reason: f.name);
      expect(FreePlan.canUse(f, isPlus: true), isTrue, reason: f.name);
    }
  });

  test('the free hook stays free: the station, showers, eclipses, pairings', () {
    for (final t in [
      SkyEventType.iss,
      SkyEventType.meteorShower,
      SkyEventType.lunarEclipse,
      SkyEventType.solarEclipse,
      SkyEventType.planetPairing,
    ]) {
      expect(t.plusOnly, isFalse, reason: t.name);
    }
    for (final t in [SkyEventType.starlinkTrain, SkyEventType.tiangong, SkyEventType.rocketLaunch, SkyEventType.auroraNow]) {
      expect(t.plusOnly, isTrue, reason: t.name);
    }
  });
}
