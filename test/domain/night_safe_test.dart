import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/sky/night_safe.dart';

void main() {
  test('the switch always wins away from outside screens', () {
    expect(nightVisionNow(manual: true, auto: false, outside: false, sunAltitudeDeg: 30), isTrue);
    expect(nightVisionNow(manual: false, auto: true, outside: false, sunAltitudeDeg: -30), isFalse);
  });

  test('automatic: red outside only once it is dark there', () {
    expect(nightVisionNow(manual: false, auto: true, outside: true, sunAltitudeDeg: -12), isTrue);
    expect(nightVisionNow(manual: false, auto: true, outside: true, sunAltitudeDeg: -6), isTrue);
    expect(nightVisionNow(manual: false, auto: true, outside: true, sunAltitudeDeg: -3), isFalse); // still twilight
    expect(nightVisionNow(manual: false, auto: true, outside: true, sunAltitudeDeg: null), isFalse); // no location
    expect(nightVisionNow(manual: false, auto: false, outside: true, sunAltitudeDeg: -20), isFalse);
  });

  test('what they choose on an outside screen sticks there, either way', () {
    expect(nightVisionNow(manual: false, auto: true, outside: true, sunAltitudeDeg: -20, override: false), isFalse);
    expect(nightVisionNow(manual: true, auto: false, outside: true, sunAltitudeDeg: 20, override: false), isFalse);
    expect(nightVisionNow(manual: false, auto: false, outside: true, sunAltitudeDeg: 20, override: true), isTrue);
    // ...and doesn't leak to the rest of the app.
    expect(nightVisionNow(manual: false, auto: true, outside: false, sunAltitudeDeg: -20, override: true), isFalse);
  });

  test('on by default, and it survives a round trip', () {
    expect(const LookUpSettings().nightVisionAuto, isTrue);
    final s = LookUpSettings.fromJson(const LookUpSettings(nightVisionAuto: false).toJson());
    expect(s.nightVisionAuto, isFalse);
    expect(LookUpSettings.fromJson(const {}).nightVisionAuto, isTrue); // older installs
  });
}
