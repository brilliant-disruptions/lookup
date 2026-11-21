import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/photo/shot_plan.dart';
import 'package:lookup/domain/plus/pro_nudge.dart';

void main() {
  final now = DateTime.utc(2026, 11, 21, 3);
  bool show({bool plus = false, ShotSubject? s = ShotSubject.moon, int catches = 3, DateTime? last, int notNow = 0}) =>
      showProNudge(isPlus: plus, subject: s, catches: catches, now: now, lastShown: last, notNow: notNow);

  test('free, after a catch the Pro camera would have done better: one line', () {
    expect(show(), isTrue);
    for (final s in ShotSubject.values.where((s) => s != ShotSubject.pass)) {
      expect(show(s: s), isTrue, reason: '$s');
      expect(proNudgeLine(s), isNot(contains('°')));
    }
  });

  test('never on LookUp+, never on the first catch', () {
    expect(show(plus: true), isFalse);
    expect(show(catches: 1), isFalse, reason: 'the first one is theirs to enjoy');
    expect(show(catches: 2), isTrue);
  });

  test('never for a pass (Pip catches those) or something with no Pro plan (the Sun)', () {
    expect(show(s: ShotSubject.pass), isFalse);
    expect(show(s: null), isFalse);
  });

  test('at most once a week', () {
    expect(show(last: now.subtract(const Duration(days: 2))), isFalse);
    expect(show(last: now.subtract(const Duration(days: 6, hours: 23))), isFalse);
    expect(show(last: now.subtract(const Duration(days: 7))), isTrue);
  });

  test('two "Not now"s and it never comes back', () {
    expect(show(notNow: 1), isTrue);
    expect(show(notNow: 2), isFalse);
    expect(show(notNow: 2, last: now.subtract(const Duration(days: 400))), isFalse);
  });

  test('when it was shown and the "Not now"s survive a restart', () {
    final s = const LookUpSettings().copyWith(proNudgeAt: now, proNudgeNotNow: 1);
    final back = LookUpSettings.fromJson(s.toJson());
    expect(back.proNudgeAt, now);
    expect(back.proNudgeNotNow, 1);
    expect(LookUpSettings.fromJson(const LookUpSettings().toJson()).proNudgeNotNow, 0);
  });
}
