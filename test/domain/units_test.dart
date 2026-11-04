import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/units.dart';

void main() {
  test('kilometres, rounded to a sensible step', () {
    expect(distanceWords(7.4, miles: false), '7 km');
    expect(distanceWords(43, miles: false), '45 km');
    expect(distanceWords(243, miles: false), '240 km');
  });

  test('miles, converted then rounded the same way', () {
    expect(distanceWords(1.6, miles: true), '1 mile');
    expect(distanceWords(40, miles: true), '25 miles'); // 24.9
    expect(distanceWords(300, miles: true), '190 miles'); // 186
  });

  test('miles where people read miles', () {
    for (final c in ['US', 'GB', 'us']) {
      expect(countryUsesMiles(c), isTrue, reason: c);
    }
    for (final c in ['CA', 'AU', 'DE', null]) {
      expect(countryUsesMiles(c), isFalse, reason: '$c');
    }
  });

  test('the choice is saved, and kilometres until one is made', () {
    expect(const LookUpSettings().usesMiles, isFalse);
    final s = LookUpSettings.fromJson(const LookUpSettings(miles: true).toJson());
    expect(s.miles, isTrue);
    expect(LookUpSettings.fromJson(const LookUpSettings().toJson()).miles, isNull);
  });
}
