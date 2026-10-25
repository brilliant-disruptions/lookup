import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/log/sighting.dart';
import 'package:lookup/domain/log/sky_log.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/scheduling/alert_tuning.dart';

Sighting no(String reason, DateTime at) => Sighting(eventId: 'iss:$at', seen: false, at: at, reason: reason, type: SkyEventType.iss);
Sighting yes(SkyEventType t, DateTime at, {double el = 40, double? mag}) =>
    Sighting(eventId: '${t.name}:$at', seen: true, at: at, type: t, peakElevationDeg: el, magnitude: mag, eventTime: at);

void main() {
  final now = DateTime.utc(2026, 10, 25);
  DateTime ago(int days) => now.subtract(Duration(days: days));

  group('alert tuning', () {
    test('neutral without complaints', () {
      final t = AlertTuning.from([yes(SkyEventType.iss, ago(1))], now: now);
      expect(t.isNeutral, isTrue);
      expect(t.apply(const LookUpSettings()).minIssPeakElevationDeg, 25);
    });

    test('clouds tighten the cloud cutoff, more clouds tighten more', () {
      expect(AlertTuning.from([no('clouds', ago(1)), no('clouds', ago(3))], now: now).cloudCutoffPercent, 40);
      expect(AlertTuning.from([for (var i = 0; i < 4; i++) no('clouds', ago(i + 1))], now: now).cloudCutoffPercent, 30);
    });

    test('"too low" raises minimum elevation unless low passes were seen', () {
      final t = AlertTuning.from([no('too-low', ago(1)), no('too-low', ago(2))], now: now);
      expect(t.extraMinElevationDeg, 10);
      expect(t.apply(const LookUpSettings()).minIssPeakElevationDeg, 35);
      expect(t.reasons.single, contains('Low passes'));
      final mixed = AlertTuning.from([no('too-low', ago(1)), no('too-low', ago(2)), yes(SkyEventType.iss, ago(3), el: 28)], now: now);
      expect(mixed.extraMinElevationDeg, 0);
    });

    test('old answers stop counting', () {
      expect(AlertTuning.from([no('clouds', ago(90)), no('clouds', ago(95))], now: now).isNeutral, isTrue);
    });
  });

  group('sky log', () {
    test('counts, hit rate and badges', () {
      final all = [
        for (var i = 0; i < 5; i++) yes(SkyEventType.iss, ago(30 - i), el: i == 0 ? 80 : 40, mag: i == 1 ? -3.8 : -2),
        yes(SkyEventType.starlinkTrain, ago(10)),
        yes(SkyEventType.tiangong, ago(9)),
        no('clouds', ago(8)),
      ];
      final log = SkyLog.from(all);
      expect(log.total, 7);
      expect(log.counts[SkyEventType.iss], 5);
      expect(log.hitRate, closeTo(7 / 8, 1e-9));
      final earned = {for (final b in log.badges.where((b) => b.earned)) b.id};
      expect(earned, containsAll(['first-light', 'station-spotter', 'overhead', 'venus-bright', 'train-spotter', 'both-stations']));
      expect(earned, isNot(contains('aurora-chaser')));
      expect(earned, isNot(contains('regular')));
      // first-light is earned at the earliest sighting
      expect(log.badges.firstWhere((b) => b.id == 'first-light').earnedAt, ago(30));
    });

    test('old answers without a type are inferred from the id', () {
      final s = Sighting(eventId: 'meteor-GEM:2026', seen: true, at: now);
      expect(s.inferredType, SkyEventType.meteorShower);
      expect(SkyLog.from([s]).badges.firstWhere((b) => b.id == 'meteor-watcher').earned, isTrue);
    });

    test('no hit rate with fewer than 3 answers', () {
      expect(SkyLog.from([yes(SkyEventType.iss, now)]).hitRate, isNull);
    });
  });
}
