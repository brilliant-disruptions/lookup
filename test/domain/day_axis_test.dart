import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/plan/day_axis.dart';

void main() {
  DateTime at(int h, [int m = 0]) => DateTime(2026, 10, 30, h, m);

  test('keeps an hour either side of each start and chops the rest', () {
    final axis = DayAxis.forStarts([at(5, 40), at(19, 12), at(21, 3)]);
    expect(axis.runs, [(from: 4, to: 7), (from: 18, to: 23)]);
    expect(axis.keeps(5), isTrue);
    expect(axis.keeps(12), isFalse);
    expect(axis.keptHours, 8);
  });

  test('nearby starts join into one run; the day edges clamp', () {
    final axis = DayAxis.forStarts([at(0, 10), at(23, 50)]);
    expect(axis.runs, [(from: 0, to: 2), (from: 22, to: 24)]);
    expect(axis.breakCount, 1);
  });

  test('with nothing on, the evening is shown', () {
    expect(DayAxis.forStarts(const []).runs, [(from: 20, to: 24)]);
  });

  test('positions: shown hours are linear, breaks take their width, a cut hour lands in its break', () {
    final axis = DayAxis.forStarts([at(5), at(20)]); // 4-6 and 19-21
    expect(axis.runs, [(from: 4, to: 7), (from: 19, to: 22)]);
    const per = 50.0, brk = 10.0;
    // lead break (10) + 3 h (150) + break (10) + 3 h (150) + trailing break (10)
    expect(axis.width(per, brk), 330);
    expect(axis.x(4, per, brk), 10);
    expect(axis.x(5.5, per, brk), 10 + 75);
    expect(axis.x(19, per, brk), 10 + 150 + 10);
    expect(axis.x(12, per, brk), 10 + 150 + 5, reason: 'the middle of the break that replaced it');
    expect(axis.x(2, per, brk), 5, reason: 'the lead break');
    expect(axis.breaks(per, brk), [(0.0, 10.0), (160.0, 10.0), (320.0, 10.0)]);
    // Strictly increasing in time, so rows stay ordered on the clock.
    double last = -1;
    for (var h = 0.0; h <= 24; h += 0.5) {
      final x = axis.x(h, per, brk);
      expect(x, greaterThanOrEqualTo(last));
      last = x;
    }
  });

  test('a full day has no breaks', () {
    final axis = DayAxis.forStarts([for (var h = 1; h < 24; h += 2) at(h)]);
    expect(axis.runs, [(from: 0, to: 24)]);
    expect(axis.breakCount, 0);
    expect(axis.width(10, 5), 240);
  });
}
