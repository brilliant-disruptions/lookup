import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/sky/night_safe.dart';
import 'package:lookup/domain/sky/sun.dart';

void main() {
  // Nashville, 6–7 Nov 2026: sunset about 4:45 pm CST, sunrise about 6:15 am.
  double nashville(DateTime utc) => sunAltitudeDeg(utc, 36.17, -86.78);

  test('red from sunset to sunrise, and never by day', () {
    bool at(DateTime utc) => nightVisionNow(enabled: true, sunAltitudeDeg: nashville(utc));
    expect(at(DateTime.utc(2026, 11, 6, 19)), isFalse); // 1 pm
    expect(at(DateTime.utc(2026, 11, 6, 22, 30)), isFalse); // 4:30 pm, Sun still up
    expect(at(DateTime.utc(2026, 11, 6, 23)), isTrue); // 5 pm, just set
    expect(at(DateTime.utc(2026, 11, 7, 4)), isTrue); // 10 pm
    expect(at(DateTime.utc(2026, 11, 7, 12)), isTrue); // 6 am, not up yet
    expect(at(DateTime.utc(2026, 11, 7, 12, 30)), isFalse); // 6:30 am, risen
  });

  test('sunset is when the top of the Sun goes, not its centre', () {
    // Half the disc still showing is still day: a red screen then would
    // look broken.
    expect(nightVisionNow(enabled: true, sunAltitudeDeg: -0.5), isFalse);
    expect(nightVisionNow(enabled: true, sunAltitudeDeg: -1), isTrue);
  });

  test('switched off in Settings, it never turns red, even at midnight', () {
    expect(nightVisionNow(enabled: false, sunAltitudeDeg: -40), isFalse);
  });

  test('without a location we can\'t know it\'s night, so no red', () {
    expect(nightVisionNow(enabled: true, sunAltitudeDeg: null), isFalse);
  });

  test('on by default, also for installs that had the old one-tap switch off', () {
    expect(const LookUpSettings().nightVision, isTrue);
    expect(LookUpSettings.fromJson(const {}).nightVision, isTrue);
    // The old eye's "off" was just the default, not a choice about nights.
    expect(LookUpSettings.fromJson(const {'nightVision': false}).nightVision, isTrue);
    // Switching it off in Settings sticks.
    final off = LookUpSettings.fromJson(const LookUpSettings(nightVision: false).toJson());
    expect(off.nightVision, isFalse);
  });
}
