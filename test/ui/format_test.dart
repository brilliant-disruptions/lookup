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

  // The formatter puts a narrow no-break space before AM and PM.
  String plain(String s) => s.replaceAll('\u202f', ' ');

  test('times follow the phone\'s clock: 24-hour where it\'s set', () {
    final nine = DateTime(2026, 11, 21, 21, 5).toUtc();
    addTearDown(() => use24HourClock = false);
    use24HourClock = false;
    expect(plain(fmtTime(nine)), '9:05 PM');
    use24HourClock = true;
    expect(fmtTime(nine), '21:05');
    expect(fmtTimeSeconds(nine), '21:05:00');
    expect(fmtDayShortTime(nine), endsWith('21:05'));
  });

  test('a row\'s day and time, short: today, yesterday, a weekday', () {
    final now = DateTime.now();
    DateTime at(int days) => DateTime(now.year, now.month, now.day + days, 4, 52).toUtc();
    expect(plain(fmtDayShortTime(at(0))), 'Today 4:52 AM');
    expect(plain(fmtDayShortTime(at(-1))), 'Yesterday 4:52 AM');
    expect(plain(fmtDayShortTime(at(-3))), matches(RegExp(r'^(Mon|Tue|Wed|Thu|Fri|Sat|Sun) 4:52 AM$')));
  });

  test('noon to five is the afternoon, not tonight', () {
    final now = DateTime.now();
    expect(fmtDay(DateTime(now.year, now.month, now.day, 14, 15).toUtc()), 'This afternoon');
    expect(fmtDay(DateTime(now.year, now.month, now.day, 21).toUtc()), 'Tonight');
    expect(fmtDay(DateTime(now.year, now.month, now.day + 1, 14).toUtc()), 'Tomorrow afternoon');
    expect(fmtDay(DateTime(now.year, now.month, now.day, 5).toUtc()), 'This morning');
  });
}
