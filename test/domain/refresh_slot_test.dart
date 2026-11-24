import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/scheduling/refresh_slot.dart';

void main() {
  final now = DateTime.utc(2026, 11, 24, 12);
  bool due(Duration? age, int minute, int slot, {bool bg = true}) => feedDue(
      fetchedAt: age == null ? null : now.subtract(age), now: now, localMinute: minute, slotMinute: slot, background: bg);

  test('slots spread over the quiet hours, never into the evening', () {
    final r = Random(7);
    final slots = [for (var i = 0; i < 10000; i++) pickRefreshSlot(r)];
    expect(slots.reduce(min), greaterThanOrEqualTo(slotFirstMinute));
    expect(slots.reduce(max) + slotWindow.inMinutes, lessThanOrEqualTo(16 * 60), reason: 'the window closes by 4 PM');
    // Even: no hour holds much more than its share.
    final perHour = <int, int>{};
    for (final s in slots) {
      perHour.update(s ~/ 60, (n) => n + 1, ifAbsent: () => 1);
    }
    final share = slots.length / perHour.length;
    for (final n in perHour.values) {
      expect(n, inInclusiveRange(share * 0.85, share * 1.15));
    }
  });

  test('at most once a day: one window a day and 20 h apart', () {
    expect(due(const Duration(hours: 19, minutes: 59), 300, 240), isFalse);
    expect(due(const Duration(hours: 20), 300, 240), isTrue);
    // Each day's window is the only time it's due (until overdue).
    var downloads = 0;
    DateTime? last;
    for (var m = 0; m < 7 * 24 * 60; m += 15) {
      final t = now.add(Duration(minutes: m));
      if (feedDue(fetchedAt: last, now: t, localMinute: (720 + m) % 1440, slotMinute: 240, background: true)) {
        downloads++;
        last = t;
      }
    }
    expect(downloads, 7, reason: 'one a day, including the first');
  });

  test('the window wraps past midnight', () {
    expect(inSlotWindow(30, 23 * 60), isTrue);
    expect(inSlotWindow(4 * 60, 23 * 60), isFalse);
  });

  test('with the app open: only a missing or overdue feed', () {
    expect(due(null, 1200, 240, bg: false), isTrue);
    expect(due(const Duration(hours: 30), 260, 240, bg: false), isFalse);
    expect(due(overdueAfter, 1200, 240, bg: false), isTrue);
  });
}
