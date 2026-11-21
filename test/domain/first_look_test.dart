import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/onboarding/first_look.dart';

void main() {
  final dusk = DateTime.utc(2026, 11, 21, 23, 10); // sun −6° at Nashville, about 5:10 PM
  final window = (start: dusk, end: DateTime.utc(2026, 11, 22, 11, 50));

  group('which moment of their sky', () {
    test('in the daytime: tonight, once it is properly dark, and it says so', () {
      final f = firstLookTime(DateTime.utc(2026, 11, 21, 18), window);
      expect(f.isNow, isFalse);
      expect(f.at, dusk.add(firstLookAfterDusk));
    });

    test('after dark: right now', () {
      final at = DateTime.utc(2026, 11, 22, 3);
      expect(firstLookTime(at, window), (at: at, isNow: true));
    });

    test('just before dark: a little later tonight', () {
      final f = firstLookTime(dusk.subtract(const Duration(minutes: 10)), window);
      expect(f.isNow, isFalse);
      expect(f.at, dusk.add(firstLookAfterDusk));
    });

    test('a plan made after dark starts its window then: that is now, not 40 minutes on', () {
      final at = DateTime.utc(2026, 11, 22, 3, 33);
      expect(firstLookTime(at, (start: at, end: window.end)), (at: at, isNow: true));
    });

    test('a window that is already over (a plan from another night): now, never a time that has gone', () {
      expect(firstLookTime(window.end.add(const Duration(hours: 2)), window).isNow, isTrue);
    });

    test('no dark hours (polar summer): now', () {
      expect(firstLookTime(dusk, null).isNow, isTrue);
    });
  });

  group('the slider: why passes come at dusk and dawn', () {
    test('daytime is too bright', () {
      for (final h in [8.0, 12.0, 16.0, 17.9]) {
        expect(stationSight(h), StationSight.day, reason: '$h');
      }
    });

    test('after sunset and before sunrise it shows', () {
      expect(stationSight(19), StationSight.visible);
      expect(stationSight(5.5), StationSight.visible);
    });

    test('in the middle of the night it is in Earth\'s shadow', () {
      for (final h in [21.5, 0.0, 2.0]) {
        expect(stationSight(h), StationSight.shadow, reason: '$h');
      }
    });

    test('dark only once the Sun is 6° down, not at sunset itself', () {
      expect(stationSight(18), StationSight.day);
      expect(stationSight(18.5), StationSight.visible);
    });
  });

  test('a line for each thing Pip finds, never a number of degrees', () {
    for (final id in ['moon', 'planet:venus', 'planet:jupiter', 'planet:saturn', 'planet:mars', 'planet:mercury', 'm45']) {
      final f = firstLookFact(id, 'x');
      expect(f, isNotEmpty);
      expect(f, isNot(contains('°')));
    }
  });

  group('the pass to preview', () {
    SkyEvent ev(String id, SkyEventType type, Duration from, {bool past = false}) => SkyEvent(
          id: id,
          type: type,
          start: dusk.add(from),
          peak: dusk.add(from + const Duration(minutes: 2)),
          end: dusk.add(from + const Duration(minutes: 5)),
          peakElevationDeg: 60,
          riseAzimuthDeg: 250,
          peakAzimuthDeg: 200,
          setAzimuthDeg: 100,
          details: {if (past) 'past': true},
        );

    test('the next space station pass in the coming three days', () {
      final e = passToPreview([
        ev('iss:b', SkyEventType.iss, const Duration(days: 1)),
        ev('iss:a', SkyEventType.iss, const Duration(hours: 4)),
        ev('starlink:a', SkyEventType.starlinkTrain, const Duration(hours: 1)),
      ], dusk);
      expect(e?.id, 'iss:a');
    });

    test('none from the past, already started, or too far off', () {
      expect(passToPreview([ev('iss:x', SkyEventType.iss, const Duration(hours: -1))], dusk), isNull);
      expect(passToPreview([ev('iss:y', SkyEventType.iss, const Duration(days: 4))], dusk), isNull);
      expect(passToPreview([ev('iss:z', SkyEventType.iss, const Duration(hours: 2), past: true)], dusk), isNull);
    });
  });
}
