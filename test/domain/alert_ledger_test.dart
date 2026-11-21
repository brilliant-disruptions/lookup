import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/data/local_store.dart';
import 'package:lookup/domain/aurora/aurora_rules.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/orbit/omm.dart';
import 'package:lookup/domain/scheduling/alert_ledger.dart';
import 'package:lookup/domain/scheduling/alert_planner.dart';
import 'package:lookup/domain/scheduling/week_ahead.dart';
import 'package:lookup/domain/starlink/train_detector.dart';
import 'package:lookup/services/event_pipeline.dart';

SkyEvent ev(String id, SkyEventType type, DateTime start, {double el = 60, int? clouds, Map<String, Object?> details = const {}}) => SkyEvent(
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
      details: details,
    );

void main() {
  const planner = AlertPlanner();

  group('what has gone out stays out of the schedule', () {
    final now = DateTime.utc(2026, 10, 21, 20);
    AlertRecord rec(int id, DateTime at, {bool counts = true}) =>
        AlertRecord(id: id, eventId: 'e$id', fireAt: at, peak: at.add(const Duration(minutes: 12)), counts: counts);

    test('an alert whose time has passed is history; only the rest can be cancelled', () {
      final split = AlertLedger.at([
        rec(1, now.subtract(const Duration(minutes: 5))),
        rec(2, now.add(const Duration(minutes: 5))),
        rec(3, now.subtract(const Duration(days: 3))),
      ], now);
      expect(split.pending, {2});
      expect(split.delivered.map((r) => r.id), [1], reason: 'the three-day-old one is forgotten');
    });

    test('delivered alerts are remembered next to the new schedule, once each', () {
      final delivered = [rec(1, now.subtract(const Duration(minutes: 5)))];
      final next = AlertLedger.next(delivered, [rec(1, now.add(const Duration(hours: 1))), rec(4, now.add(const Duration(hours: 2)))]);
      expect(next.map((r) => r.id), [1, 4]);
      expect(next.first.fireAt.isAfter(now), isTrue, reason: 'planned again wins over the old record');
    });

    test('"aurora now" is remembered but doesn\'t use one of the night\'s taps', () {
      final delivered = [rec(1, now.subtract(const Duration(hours: 1))), rec(2, now.subtract(const Duration(minutes: 30)), counts: false)];
      expect(AlertLedger.alerted(delivered).keys, ['e1']);
    });

    test('survives being saved', () {
      final r = rec(7, now, counts: false);
      final back = AlertRecord.fromJson(jsonDecode(jsonEncode(r.toJson())))!;
      expect((back.id, back.eventId, back.fireAt, back.peak, back.counts), (7, 'e7', now, r.peak, false));
      expect(AlertRecord.fromJson('nonsense'), isNull);
    });
  });

  group('the night\'s cap', () {
    const s = LookUpSettings(maxAlertsPerNight: 1, isPlus: true);
    final a = ev('iss:a', SkyEventType.iss, DateTime.utc(2026, 10, 21, 19), el: 80, clouds: 0);
    final b = ev('iss:b', SkyEventType.iss, DateTime.utc(2026, 10, 21, 20, 36), el: 30, clouds: 0);
    final c = ev('starlink-x:c', SkyEventType.starlinkTrain, DateTime.utc(2026, 10, 21, 21, 30), el: 28, clouds: 0);

    test('isn\'t filled again by each refresh through the evening', () {
      final first = planner.plan(events: [a, b, c], settings: s, now: DateTime.utc(2026, 10, 21, 17), utcOffsetMinutes: 0);
      expect(first.map((p) => p.event.id).toSet(), {'iss:a'});
      // 19:30: a's alert has gone out. It has used tonight's one tap.
      final later = planner.plan(
          events: [a, b, c], settings: s, now: DateTime.utc(2026, 10, 21, 19, 30), utcOffsetMinutes: 0, alerted: {'iss:a': a.peak});
      expect(later, isEmpty);
    });

    test('an event whose heads-up has gone keeps its "go now"', () {
      final now = a.start.subtract(const Duration(minutes: 5));
      final plan = planner.plan(events: [a, b], settings: s, now: now, utcOffsetMinutes: 0, alerted: {'iss:a': a.peak});
      expect(plan.map((p) => (p.event.id, p.kind)), [('iss:a', AlertKind.goNow)]);
    });

    test('last night\'s taps don\'t count against tonight', () {
      final plan = planner.plan(
          events: [b],
          settings: s,
          now: DateTime.utc(2026, 10, 21, 17),
          utcOffsetMinutes: 0,
          alerted: {'iss:y': DateTime.utc(2026, 10, 20, 20)});
      expect(plan.map((p) => p.event.id).toSet(), {'iss:b'});
    });
  });

  group('quiet hours', () {
    const s = LookUpSettings(); // quiet 23:00 to 05:30, a 10-minute lead
    bool quiet(DateTime t) => s.quietHours.contains(t.hour * 60 + t.minute);

    test('a pass just after they end: the heads-up waits for them to end, and says what\'s left', () {
      final e = ev('iss:dawn', SkyEventType.iss, DateTime.utc(2026, 10, 22, 5, 35), clouds: 0);
      final plan = planner.plan(events: [e], settings: s, now: DateTime.utc(2026, 10, 21, 20), utcOffsetMinutes: 0);
      expect(plan, isNotEmpty);
      for (final a in plan) {
        expect(quiet(a.fireAt), isFalse, reason: '${a.kind.name} at ${a.fireAt}');
      }
      final headsUp = plan.firstWhere((a) => a.kind == AlertKind.headsUp);
      expect(headsUp.fireAt, DateTime.utc(2026, 10, 22, 5, 30));
      expect(headsUp.title, contains('5 min'));
    });

    test('too close to their end for a heads-up to help: only "go now", if that\'s outside them', () {
      final e = ev('iss:close', SkyEventType.iss, DateTime.utc(2026, 10, 22, 5, 31), clouds: 0);
      final plan = planner.plan(events: [e], settings: s, now: DateTime.utc(2026, 10, 21, 20), utcOffsetMinutes: 0);
      expect(plan.map((a) => a.kind), [AlertKind.goNow]);
      expect(plan.single.fireAt, DateTime.utc(2026, 10, 22, 5, 30));
    });

    test('an ordinary evening pass is unchanged', () {
      final e = ev('iss:eve', SkyEventType.iss, DateTime.utc(2026, 10, 21, 21), clouds: 0);
      final plan = planner.plan(events: [e], settings: s, now: DateTime.utc(2026, 10, 21, 20), utcOffsetMinutes: 0);
      expect(plan.first.fireAt, DateTime.utc(2026, 10, 21, 20, 50));
      expect(plan.first.title, contains('10 min'));
    });
  });

  group('old orbital elements', () {
    final iss = OmmRecord.listFromJson(jsonDecode(File('test/fixtures/iss_omm.json').readAsStringSync()));
    final starlink = OmmRecord.listFromJson(jsonDecode(File('test/fixtures/starlink_sample.json').readAsStringSync()));
    const s = LookUpSettings(
        latitude: 36.17,
        longitude: -86.78,
        isPlus: true,
        maxAlertsPerNight: 9,
        clearSkyOnly: false,
        quietHours: QuietHours(startMinute: 0, endMinute: 0));

    List<PlannedAlert> planAt(int days) {
      final now = iss.first.epoch.add(Duration(days: days));
      final events = const EventPipeline().build(PipelineInputs(settings: s, now: now, iss: iss, starlink: starlink));
      return [
        for (final p in planner.plan(events: events, settings: s, now: now, utcOffsetMinutes: -360, horizon: const Duration(days: 7)))
          if (const {SkyEventType.iss, SkyEventType.tiangong, SkyEventType.starlinkTrain}.contains(p.event.type)) p,
      ];
    }

    test('elements a week or so old still tap', () {
      // The fixture's first good week of ISS evenings over Nashville starts about day 8.
      expect(planAt(8).where((p) => p.event.type == SkyEventType.iss), isNotEmpty);
    });

    // The download keeps failing, or the feed refuses: the cached elements
    // age, and a pass worked out from them drifts by minutes, then more.
    test('nobody is sent outside from elements weeks or months old', () {
      for (final days in [30, 60, 180, 365]) {
        expect(planAt(days), isEmpty, reason: '$days days old');
      }
    });

    test('a Starlink train isn\'t one for ever: the count runs on from the elements\' date', () {
      final groups = TrainDetector.detect(starlink);
      expect(groups, isNotEmpty);
      final g = groups.first;
      expect(g.isTrainPhaseAt(g.latestEpoch), isTrue);
      expect(g.isTrainPhaseAt(g.latestEpoch.add(const Duration(days: 365))), isFalse);
      expect(TrainDetector.detect(starlink, now: g.latestEpoch.add(const Duration(days: 365))), isEmpty);
    });

    test('a station pass is tapped for up to two weeks from its elements, a train up to five days', () {
      final epoch = DateTime.utc(2026, 10, 20);
      SkyEvent pass(SkyEventType t, int days) => ev('x', t, epoch.add(Duration(days: days)),
          details: {'omm': {'EPOCH': '2026-10-20T00:00:00.000000'}});
      expect(AlertPlanner.elementsFresh(pass(SkyEventType.iss, 13)), isTrue);
      expect(AlertPlanner.elementsFresh(pass(SkyEventType.iss, 15)), isFalse);
      expect(AlertPlanner.elementsFresh(pass(SkyEventType.starlinkTrain, 4)), isTrue);
      expect(AlertPlanner.elementsFresh(pass(SkyEventType.starlinkTrain, 6)), isFalse);
      expect(AlertPlanner.elementsFresh(ev('m', SkyEventType.meteorShower, epoch.add(const Duration(days: 300)))), isTrue);
    });
  });

  group('aurora now', () {
    test('needs a properly dark sky: not the all-night twilight of a northern summer', () {
      // Aberdeen at local midnight on the solstice: the Sun is 9° down, its lowest all night.
      final t = DateTime.utc(2026, 6, 21, 0, 10);
      final d = auroraNow(now: t, latDeg: 57.15, lonDeg: -2.1, estimatedKp: 7, ovationProbability: 60, cloudCoverPercent: 0);
      expect(d.alert, isFalse);
      expect(d.reason, 'not dark');
      // The same storm in October's dark.
      final oct = auroraNow(
          now: DateTime.utc(2026, 10, 21, 0, 10), latDeg: 57.15, lonDeg: -2.1, estimatedKp: 7, ovationProbability: 60, cloudCoverPercent: 0);
      expect(oct.alert, isTrue);
    });

    final dark = DateTime.utc(2026, 10, 22, 9); // 1 AM in Fairbanks
    const fairbanks = LookUpSettings(latitude: 64.8, longitude: -147.7, isPlus: true);
    List<SkyEvent> auroraFrom(AuroraSnapshot snap, {LookUpSettings s = fairbanks}) => const EventPipeline()
        .build(PipelineInputs(settings: s, now: dark, aurora: snap))
        .where((e) => e.type == SkyEventType.auroraNow)
        .toList();

    test('only from a reading taken within the hour', () {
      AuroraSnapshot at(Duration age) =>
          AuroraSnapshot(fetchedAt: dark.subtract(age), kpNow: 7, forecast: const [], ovationProbability: 70, latitude: 64.8, longitude: -147.7);
      expect(auroraFrom(at(const Duration(minutes: 20))), hasLength(1));
      expect(auroraFrom(at(const Duration(hours: 2))), isEmpty, reason: 'the feed has been down two hours');
      expect(auroraFrom(at(const Duration(days: 2))), isEmpty, reason: 'the storm of two days ago');
    });

    test('never from a reading taken for somewhere else', () {
      final elsewhere = AuroraSnapshot(
          fetchedAt: dark.subtract(const Duration(minutes: 5)), kpNow: 7, forecast: const [], ovationProbability: 70, latitude: 60, longitude: -150);
      expect(auroraFrom(elsewhere), isEmpty);
      expect(elsewhere.currentFor(dark, 60.2, -150.1), isTrue);
    });

    test('says which way to face: south from the southern hemisphere', () {
      const hobart = LookUpSettings(latitude: -42.88, longitude: 147.33, isPlus: true);
      final night = DateTime.utc(2026, 6, 21, 14); // midnight in Hobart, midwinter
      final e = const EventPipeline()
          .build(PipelineInputs(
              settings: hobart,
              now: night,
              aurora: AuroraSnapshot(fetchedAt: night, kpNow: 8, forecast: const [], ovationProbability: 80, latitude: -42.88, longitude: 147.33)))
          .where((e) => e.type == SkyEventType.auroraNow)
          .single;
      expect(auroraFace(e), 'south');
      expect(AlertPlanner.headsUpBody(e), startsWith('Find a dark spot and look south.'));
      final north = auroraFrom(AuroraSnapshot(fetchedAt: dark, kpNow: 7, forecast: const [], ovationProbability: 70)).single;
      expect(AlertPlanner.headsUpBody(north), startsWith('Find a dark spot and look north.'));
    });
  });

  test('the week-ahead note never promises a tap that quiet hours will keep silent', () {
    final now = DateTime(2026, 11, 18, 20).toUtc();
    final sunday = WeekAhead.nextSend(now).toLocal();
    const on = LookUpSettings(latitude: 36.17, longitude: -86.78, onboarded: true);
    final at = DateTime(sunday.year, sunday.month, sunday.day + 9, 4, 50).toUtc(); // 4:50 AM: inside quiet hours
    final note = WeekAhead.of(events: [ev('iss:q', SkyEventType.iss, at, clouds: 0)], settings: on, now: now);
    expect(note, isNull, reason: 'nothing it would tap for, so nothing to say');
    final evening = DateTime(sunday.year, sunday.month, sunday.day + 9, 19, 50).toUtc();
    expect(WeekAhead.of(events: [ev('iss:e', SkyEventType.iss, evening, clouds: 0)], settings: on, now: now)!.body,
        contains('Pip will tap you'));
  });
}
