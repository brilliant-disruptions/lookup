import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/ui/format.dart';

void main() {
  test('never "Appears in 0s": the last few seconds say it is appearing now', () {
    expect(fmtAppears(const Duration(minutes: 4, seconds: 10)), 'Appears in 4m 10s');
    expect(fmtAppears(const Duration(seconds: 12)), 'Appears in 12s');
    expect(fmtAppears(const Duration(seconds: 4)), 'Appearing now');
    expect(fmtAppears(Duration.zero), 'Appearing now');
    expect(fmtAppears(const Duration(seconds: -3)), 'Appearing now');
  });

  test('nerd mode numbers: a tenth of a degree, a real minus, RA in hours', () {
    expect(nerdPosition(182.44, 24.06), 'Az 182.4° · Alt 24.1°');
    expect(nerdPosition(-10, -2), 'Az 350.0° · Alt \u22122.0°');
    expect(nerdMagnitude(-3.14), 'Mag \u22123.1');
    expect(nerdMagnitude(0.6), 'Mag 0.6');
    // Betelgeuse: RA 88.79°, Dec +7.41°.
    expect(nerdRaDec(88.79, 7.41), 'RA 5h 55.2m · Dec 7.4°');
    expect(nerdRaDec(83.82, -5.39), 'RA 5h 35.3m · Dec \u22125.4°');
  });
}
