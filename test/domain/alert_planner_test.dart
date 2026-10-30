import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/scheduling/alert_planner.dart';
import 'package:lookup/domain/scheduling/alert_tuning.dart';

SkyEvent ev(String id, SkyEventType type, DateTime start,
        {double el = 60, int? clouds, bool estimate = false,
        Map<String, Object?> details = const {}}) =>
    SkyEvent(
      id: id,
      type: type,
      start: start,
      peak: start.add(const Duration(minutes: 2)),
      end: start.add(const Duration(minutes: 4)),
      peakElevationDeg: el,
      riseAzimuthDeg: 247,
      peakAzimuthDeg: 180,
      setAzimuthDeg: 100,
      cloudCoverPercent: clouds,
      isEstimate: estimate,
      details: details,
    );

void main() {
  const planner = AlertPlanner();
  final now = DateTime.utc(2026, 10, 21, 20); // 3pm CDT
  const cdt = -5 * 60;
  const plus = LookUpSettings(isPlus: true);

  test('heads-up and go-now with stable ids and readable copy', () {
    final e = ev('iss:a', SkyEventType.iss, now.add(const Duration(hours: 5)),
        clouds: 10, details: {'brightness': 'brighter than any star'});
    final plan = planner.plan(
        events: [e], settings: plus, now: now, utcOffsetMinutes: cdt);
    expect(plan.length, 2);
    expect(plan[0].kind, AlertKind.headsUp);
    expect(plan[0].fireAt, e.start.subtract(const Duration(minutes: 10)));
    expect(plan[0].title, 'ISS flyover in 10 min');
    expect(plan[0].body,
        'Brighter than any star, rising in the west-southwest, high in the sky at its best, 4 min. Clear skies.');
    expect(plan[1].kind, AlertKind.goNow);
    expect(plan[1].fireAt, e.start.subtract(const Duration(minutes: 1)));
    expect(plan[1].body, 'Look west-southwest. High in the sky at its best.');
    expect(plan[0].notificationId, isNot(plan[1].notificationId));
    expect(AlertPlanner.notificationIdFor('iss:a', AlertKind.headsUp),
        plan[0].notificationId);
    expect(plan[0].notificationId, greaterThan(0));
  });

  test('free users are not tapped for Plus-only events', () {
    final sl = ev('sl:a', SkyEventType.starlinkTrain,
        now.add(const Duration(hours: 5)));
    final iss = ev('iss:a', SkyEventType.iss, now.add(const Duration(hours: 6)));
    final free = planner.plan(
        events: [sl, iss], settings: const LookUpSettings(), now: now,
        utcOffsetMinutes: cdt);
    expect(free.map((a) => a.event.id).toSet(), {'iss:a'});
    final paid = planner.plan(
        events: [sl, iss], settings: plus, now: now, utcOffsetMinutes: cdt);
    expect(paid.map((a) => a.event.id).toSet(), {'sl:a', 'iss:a'});
  });

  test('cloudy events are suppressed only when clearSkyOnly', () {
    final e = ev('iss:a', SkyEventType.iss, now.add(const Duration(hours: 5)),
        clouds: 85);
    expect(planner.plan(events: [e], settings: plus, now: now,
        utcOffsetMinutes: cdt), isEmpty);
    final relaxed = planner.plan(
        events: [e], settings: plus.copyWith(clearSkyOnly: false), now: now,
        utcOffsetMinutes: cdt);
    expect(relaxed.first.body, endsWith('Cloudy (85%) — might not see it.'));
  });

  test('quiet hours block everything except aurora when wake-me is on', () {
    // 03:00 CDT = 08:00Z next day
    final lateIss = ev('iss:late', SkyEventType.iss, now.add(const Duration(hours: 12)));
    final lateAurora = ev('au:late', SkyEventType.auroraNow,
        now.add(const Duration(hours: 12, minutes: 30)));
    final quiet = planner.plan(
        events: [lateIss, lateAurora], settings: plus, now: now,
        utcOffsetMinutes: cdt);
    expect(quiet, isEmpty);
    final wake = planner.plan(
        events: [lateIss, lateAurora],
        settings: plus.copyWith(auroraWakeMe: true), now: now,
        utcOffsetMinutes: cdt);
    expect(wake.map((a) => a.event.id).toSet(), {'au:late'});
    expect(wake.first.body, 'Find a dark spot and look north.');
  });

  test('nightly cap keeps the best-scored events', () {
    final evening = now.add(const Duration(hours: 4)); // 7pm CDT
    final events = [
      ev('a', SkyEventType.iss, evening, el: 30),
      ev('b', SkyEventType.iss, evening.add(const Duration(hours: 1)), el: 80),
      ev('c', SkyEventType.iss, evening.add(const Duration(hours: 2)), el: 55),
      // next night
      ev('d', SkyEventType.iss, evening.add(const Duration(hours: 24)), el: 20),
    ];
    final plan = planner.plan(
        events: events, settings: plus.copyWith(goNowNudge: false), now: now,
        utcOffsetMinutes: cdt);
    expect(plan.map((a) => a.event.id), ['b', 'c', 'd']);
  });

  test('estimates and past events get no go-now nudge', () {
    final est = ev('iss:e', SkyEventType.iss, now.add(const Duration(hours: 5)),
        estimate: true);
    final plan = planner.plan(
        events: [est], settings: plus, now: now, utcOffsetMinutes: cdt);
    expect(plan.length, 1);
    expect(plan.single.body, contains('(estimate)'));
    final soon = ev('iss:s', SkyEventType.iss, now.add(const Duration(minutes: 5)));
    final planSoon = planner.plan(
        events: [soon], settings: plus, now: now, utcOffsetMinutes: cdt);
    expect(planSoon.map((a) => a.kind), [AlertKind.goNow]);
  });

  test('Starlink copy mentions the line of lights', () {
    final sl = ev('sl:a', SkyEventType.starlinkTrain,
        now.add(const Duration(hours: 5)),
        details: {'count': 27, 'label': 'Starlink train'});
    final plan = planner.plan(
        events: [sl], settings: plus.copyWith(goNowNudge: false), now: now,
        utcOffsetMinutes: cdt);
    expect(plan.single.title, 'Starlink train in 10 min');
    expect(plan.single.body, startsWith('A line of ~27 lights, rising in the'));
  });

  test('settings and quiet hours round-trip through JSON', () {
    final s = plus.copyWith(
        latitude: 1, longitude: 2, leadMinutes: 20,
        quietHours: const QuietHours(startMinute: 60, endMinute: 120));
    final rt = LookUpSettings.fromJson(s.toJson());
    expect(rt.leadMinutes, 20);
    expect(rt.isPlus, isTrue);
    expect(rt.quietHours.contains(90), isTrue);
    expect(rt.quietHours.contains(121), isFalse);
    expect(QuietHours.defaults.contains(23 * 60 + 30), isTrue);
    expect(QuietHours.defaults.contains(2 * 60), isTrue);
    expect(QuietHours.defaults.contains(12 * 60), isFalse);
  });

  test('learned cloud cutoff suppresses a 50% cloudy pass', () {
    final e = ev('iss:c', SkyEventType.iss, now.add(const Duration(hours: 5)), clouds: 50);
    expect(planner.plan(events: [e], settings: plus, now: now, utcOffsetMinutes: cdt), isNotEmpty);
    expect(
        planner.plan(events: [e], settings: plus, now: now, utcOffsetMinutes: cdt,
            tuning: const AlertTuning(cloudCutoffPercent: 40)),
        isEmpty);
  });

  test('new event types: copy, toggles and the wake-me exception', () {
    final meteor = ev('meteor-GEM:2026', SkyEventType.meteorShower, now.add(const Duration(hours: 5)),
        details: {'shower': 'Geminids', 'perHour': 60, 'moonIllumination': 0.1, 'moonUp': false});
    final launch = ev('launch:x', SkyEventType.rocketLaunch, now.add(const Duration(hours: 6)),
        details: {'name': 'Falcon 9', 'distanceKm': 210});
    final plan = planner.plan(events: [meteor, launch], settings: plus.copyWith(goNowNudge: false), now: now, utcOffsetMinutes: cdt);
    expect(plan.map((a) => a.title), ['Geminids tonight', 'Rocket launch in 10 min']);
    expect(plan.first.body, startsWith('Up to ~60 an hour'));
    expect(plan.last.body, contains('Falcon 9, 210 km away'));
    final off = planner.plan(events: [meteor, launch], settings: plus.copyWith(meteorsEnabled: false, launchesEnabled: false), now: now, utcOffsetMinutes: cdt);
    expect(off, isEmpty);
    // Launches are Plus; meteors are free.
    final free = planner.plan(events: [meteor, launch], settings: const LookUpSettings(goNowNudge: false), now: now, utcOffsetMinutes: cdt);
    expect(free.map((a) => a.event.id), ['meteor-GEM:2026']);
    // 3 AM eclipse passes quiet hours only with wake-me.
    final eclipse = ev('eclipse:x', SkyEventType.lunarEclipse, now.add(const Duration(hours: 12)), details: {'label': 'Total lunar eclipse'});
    expect(planner.plan(events: [eclipse], settings: plus, now: now, utcOffsetMinutes: cdt), isEmpty);
    expect(planner.plan(events: [eclipse], settings: plus.copyWith(auroraWakeMe: true), now: now, utcOffsetMinutes: cdt), isNotEmpty);
  });

  test('planet highlights follow the Planets toggle; sky objects never push', () {
    final soon = now.add(const Duration(hours: 3));
    final hl = ev('planet-saturn-opposition:20261004', SkyEventType.planetHighlight, soon,
        details: {'planet': 'Saturn', 'label': 'Saturn at its brightest', 'brightness': 'as bright as the brightest stars'});
    final on = planner.plan(events: [hl], settings: plus, now: now, utcOffsetMinutes: cdt);
    expect(on.first.title, 'Saturn at its brightest');
    expect(planner.plan(events: [hl], settings: plus.copyWith(pairingsEnabled: false), now: now, utcOffsetMinutes: cdt), isEmpty);
    final obj = ev('obj:m31', SkyEventType.skyObject, soon, details: {'name': 'Andromeda Galaxy'});
    expect(planner.plan(events: [obj], settings: plus, now: now, utcOffsetMinutes: cdt), isEmpty);
  });

  test('transits and satellites-tonight are listed but never pushed', () {
    final soon = now.add(const Duration(hours: 3));
    final plan = planner.plan(events: [
      ev('transit-sun:x', SkyEventType.issTransit, soon, details: {'body': 'Sun'}),
      ev('sat:hst', SkyEventType.satellitePass, soon.add(const Duration(hours: 1))),
    ], settings: plus, now: now, utcOffsetMinutes: cdt);
    expect(plan, isEmpty);
  });

  test('the paywall lists only Plus-only alerts we would push, soonest first', () {
    final ahead = AlertPlanner.plusOnlyAhead([
      ev('iss:free', SkyEventType.iss, now.add(const Duration(hours: 2))),
      ev('starlink:b', SkyEventType.starlinkTrain, now.add(const Duration(days: 2))),
      ev('tiangong:a', SkyEventType.tiangong, now.add(const Duration(days: 1))),
      ev('starlink:gone', SkyEventType.starlinkTrain, now.subtract(const Duration(hours: 1))),
      ev('tiangong:far', SkyEventType.tiangong, now.add(const Duration(days: 20))),
      ev('aurora-outlook:x', SkyEventType.auroraOutlook, now.add(const Duration(hours: 3))),
    ], now);
    expect(ahead.map((e) => e.id), ['tiangong:a', 'starlink:b']);
    final many = [for (var i = 1; i <= 5; i++) ev('starlink:$i', SkyEventType.starlinkTrain, now.add(Duration(hours: i)))];
    expect(AlertPlanner.plusOnlyAhead(many, now).length, 3);
  });

  group('snooze ("Remind me in 5 min")', () {
    test('fires five minutes later with a fresh lead time', () {
      final e = ev('iss:s', SkyEventType.iss, now.add(const Duration(minutes: 10)));
      final r = AlertPlanner.snooze(e, now)!;
      expect(r.fireAt, now.add(const Duration(minutes: 5)));
      expect(r.kind, AlertKind.snooze);
      expect(r.title, 'ISS flyover in 5 min');
      expect(r.notificationId, isNot(AlertPlanner.notificationIdFor(e.id, AlertKind.headsUp)));
    });

    test('never later than a minute before the start', () {
      final e = ev('iss:s', SkyEventType.iss, now.add(const Duration(minutes: 4)));
      final r = AlertPlanner.snooze(e, now)!;
      expect(r.fireAt, e.start.subtract(const Duration(minutes: 1)));
      expect(r.title, 'ISS flyover in 1 min');
    });

    test('nothing when the event is about to start', () {
      final e = ev('iss:s', SkyEventType.iss, now.add(const Duration(seconds: 90)));
      expect(AlertPlanner.snooze(e, now), isNull);
    });
  });
}
