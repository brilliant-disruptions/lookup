import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/scheduling/week_ahead.dart';

void main() {
  // A Wednesday evening, local.
  final now = DateTime(2026, 11, 18, 20).toUtc();
  final sunday = WeekAhead.nextSend(now);
  const on = LookUpSettings(latitude: 36.17, longitude: -86.78, onboarded: true);

  SkyEvent ev(String id, SkyEventType type, Duration afterSend, {Map<String, Object?> details = const {}}) {
    final at = sunday.add(afterSend);
    return SkyEvent(
        id: id,
        type: type,
        start: at,
        peak: at,
        end: at.add(const Duration(minutes: 5)),
        peakElevationDeg: 50,
        riseAzimuthDeg: 200,
        peakAzimuthDeg: 180,
        setAzimuthDeg: 100,
        details: details);
  }

  test('sent on Sunday at 5:40 PM local, the next one after now', () {
    final l = sunday.toLocal();
    expect((l.weekday, l.hour, l.minute), (DateTime.sunday, 17, 40));
    expect(sunday.isAfter(now), isTrue);
    expect(sunday.difference(now) <= const Duration(days: 7), isTrue);
    expect(WeekAhead.nextSend(sunday), sunday.add(const Duration(days: 7)), reason: 'right at the time: the next week\'s');
  });

  test('counts the week\'s sights by kind and says when the first is', () {
    final n = WeekAhead.of(events: [
      ev('iss:1', SkyEventType.iss, const Duration(days: 2, hours: 1)),
      ev('iss:2', SkyEventType.iss, const Duration(days: 3)),
      ev('iss:3', SkyEventType.iss, const Duration(days: 4)),
      ev('meteor-GEM:2026', SkyEventType.meteorShower, const Duration(days: 5), details: {'shower': 'Geminids'}),
      ev('iss:far', SkyEventType.iss, const Duration(days: 9)), // after the week
    ], settings: on, now: now)!;
    expect(n.at, sunday);
    expect(n.title, 'Your week ahead');
    expect(n.body, startsWith('3 space station passes and the Geminids at their best this week. First up: '));
  });

  test('never mentions what they turned off, or LookUp+ on free', () {
    final n = WeekAhead.of(events: [
      ev('starlink:1', SkyEventType.starlinkTrain, const Duration(days: 1)), // Plus-only on free
      ev('meteor-GEM:2026', SkyEventType.meteorShower, const Duration(days: 2), details: {'shower': 'Geminids'}),
      ev('outlook', SkyEventType.auroraOutlook, const Duration(days: 1)), // never pushed
    ], settings: on.copyWith(meteorsEnabled: false), now: now);
    expect(n, isNull, reason: 'nothing left they\'d be tapped for');
    final plus = WeekAhead.of(events: [ev('starlink:1', SkyEventType.starlinkTrain, const Duration(days: 1))], settings: on.copyWith(isPlus: true), now: now)!;
    expect(plus.body, startsWith('A Starlink train this week.'));
    expect(plus.body.toLowerCase(), isNot(contains('lookup+')));
  });

  test('a quiet week says when the next thing is', () {
    final n = WeekAhead.of(events: [ev('iss:far', SkyEventType.iss, const Duration(days: 10))], settings: on, now: now)!;
    expect(n.title, 'A quiet week overhead');
    expect(n.body, startsWith('A space station pass is next, on '));
    expect(n.body, contains('Pip will tap you'));
  });

  test('off, not set up yet, or nothing coming at all: no note', () {
    final e = [ev('iss:1', SkyEventType.iss, const Duration(days: 1))];
    expect(WeekAhead.of(events: e, settings: on.copyWith(weekAhead: false), now: now), isNull);
    expect(WeekAhead.of(events: e, settings: const LookUpSettings(), now: now), isNull);
    expect(WeekAhead.of(events: const [], settings: on, now: now), isNull);
  });

  test('no degrees in it', () {
    final n = WeekAhead.of(events: [ev('iss:1', SkyEventType.iss, const Duration(days: 1))], settings: on, now: now)!;
    expect('${n.title} ${n.body}', isNot(contains('°')));
  });
}
