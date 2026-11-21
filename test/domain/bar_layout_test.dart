import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/plan/bar_layout.dart';

void main() {
  const w = 340.0;
  double x(double hour) => hour / 14 * w; // hours after 5 PM

  List<BarSlot> run(List<double> hours, List<double> named) =>
      layoutBar(timeX: [for (final h in hours) x(h)], namedWidth: named, width: w);

  bool overlap(BarSlot a, BarSlot b) => a.lane == b.lane && a.left < b.left + b.width && b.left < a.left + a.width;

  test('a lone sight keeps its icon on its time, with its name', () {
    final s = run([2.2], [60]).single;
    expect(s.lane, 0);
    expect(s.named, isTrue);
    expect(s.left + 13, closeTo(x(2.2), 1e-9), reason: 'icon centred on the time');
  });

  test('stacked sights never move off their time: they drop a row instead', () {
    final s = run([2.2, 3.7, 4.7], [62, 92, 86]);
    for (var i = 0; i < s.length; i++) {
      expect(s[i].left + 13, closeTo(x([2.2, 3.7, 4.7][i]), 1e-9), reason: 'sight $i stays on its time');
    }
    expect(s.map((e) => e.lane).toSet().length, greaterThan(1));
    for (var i = 0; i < s.length; i++) {
      for (var j = i + 1; j < s.length; j++) {
        expect(overlap(s[i], s[j]), isFalse, reason: '$i and $j');
      }
    }
  });

  test('when the name will not fit, the icon alone stays on its time in the first rows', () {
    final s = run([2.0, 2.4, 2.8, 3.2], [90, 90, 90, 90]);
    for (var i = 0; i < s.length; i++) {
      for (var j = i + 1; j < s.length; j++) {
        expect(overlap(s[i], s[j]), isFalse);
      }
    }
    expect(s.every((e) => e.lane < barMaxLanes), isTrue);
  });

  test('a sight near the end of the night is icon only, inside the bar', () {
    final s = run([13.9], [90]).single;
    expect(s.named, isFalse);
    expect(s.left + s.width, lessThanOrEqualTo(w));
  });

  test('sights within minutes of each other still never overlap while rows last', () {
    final s = run([3.0, 3.01, 3.02, 3.03], [60, 60, 60, 60]);
    for (var i = 0; i < s.length; i++) {
      for (var j = i + 1; j < s.length; j++) {
        expect(overlap(s[i], s[j]), isFalse);
      }
    }
  });
}
