import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/log/review_ask.dart';
import 'package:lookup/domain/models/settings.dart';

void main() {
  final now = DateTime.utc(2026, 11, 21, 22);
  final settled = now.subtract(const Duration(days: 10));
  bool due({int catches = 5, DateTime? onboardedAt, DateTime? last, int asks = 0, bool practice = false}) =>
      ReviewAsk.due(catches: catches, now: now, onboardedAt: onboardedAt ?? settled, lastAskedAt: last, asks: asks, practice: practice);

  test('after a few catches and a few days, it asks', () => expect(due(), isTrue));
  test('never on the first catches', () => expect(due(catches: 2), isFalse));
  test('never in the first days', () => expect(due(onboardedAt: now.subtract(const Duration(days: 1))), isFalse));
  test('never for a practice or preview catch', () => expect(due(practice: true), isFalse));
  test('then not again for four months', () {
    expect(due(last: now.subtract(const Duration(days: 30))), isFalse);
    expect(due(last: now.subtract(const Duration(days: 121))), isTrue);
  });
  test('three times at most, ever', () => expect(due(asks: 3, last: now.subtract(const Duration(days: 400))), isFalse));
  test('when and how often survive a restart; the week-ahead note is on unless turned off', () {
    final s = LookUpSettings.fromJson(LookUpSettings(reviewAskedAt: now, reviewAsks: 2, weekAhead: false).toJson());
    expect((s.reviewAskedAt, s.reviewAsks, s.weekAhead), (now, 2, false));
    expect(LookUpSettings.fromJson(const {}).weekAhead, isTrue);
  });
}
