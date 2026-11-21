import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/log/catch_moment.dart';
import 'package:lookup/domain/log/sighting.dart';
import 'package:lookup/domain/log/sky_log.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/pip/pip_rest.dart';
import 'package:lookup/ui/caught_it_screen.dart' show caughtMood;
import 'package:lookup/ui/kit/pip_motion.dart';

void main() {
  test('each feeling has its own eyes, and calm is the plain open eyes', () {
    expect(PipEyes.of(PipMood.calm).lid, 0);
    expect(PipEyes.of(PipMood.happy).smileL, greaterThan(0.5), reason: 'smiling eyes');
    expect(PipEyes.of(PipMood.amazed).glint, greaterThan(0.5));
    expect(PipEyes.of(PipMood.sleepy).lid, greaterThan(0.4));
    expect(PipEyes.of(PipMood.sorry).slant, greaterThan(0), reason: 'outer corners drop');
    expect(PipEyes.of(PipMood.focused).slant, lessThan(0), reason: 'inner corners drop');
    final w = PipEyes.of(PipMood.wink);
    expect((w.smileL, w.smileR > 0.5), (0.0, true), reason: 'one eye only');
    // No two feelings look the same.
    final looks = {for (final m in PipMood.values) _key(PipEyes.of(m))};
    expect(looks.length, PipMood.values.length);
  });

  test('a new feeling eases in from the last one, and Reduce Motion shows it at once', () {
    final start = pipCharacter(10, mood: PipMood.happy, from: PipMood.calm, sinceMood: 0);
    expect(start.eyes.smileL, 0, reason: 'just changed: still calm');
    final settled = pipCharacter(10, mood: PipMood.happy, from: PipMood.calm, sinceMood: pipMoodChange);
    expect(settled.eyes.smileL, PipEyes.of(PipMood.happy).smileL);
    final still = pipCharacter(10, mood: PipMood.sorry, sinceMood: 0, still: true);
    expect(still.eyes.slant, PipEyes.of(PipMood.sorry).slant);
    expect(still.open, 1);
  });

  test('sleepy blinks are slow and heavy', () {
    // Halfway through a slow blink (4.2 s cycle, 0.9 s blink), the eyes are shut.
    expect(pipCharacter(4.2 * 3 + 0.45, mood: PipMood.sleepy, sinceMood: 5).open, lessThan(0.05));
    expect(pipCharacter(4.2 * 3 + 2, mood: PipMood.sleepy, sinceMood: 5).open, 1);
  });

  group('Pip beside the tabs', () {
    // No quiet hours here, so only the Sun decides.
    const nashville = LookUpSettings(
        latitude: 36.17, longitude: -86.78, onboarded: true, quietHours: QuietHours(startMinute: 0, endMinute: 0));
    test('sleepy while the Sun is up, calm after dark', () {
      expect(pipSleepy(now: DateTime.utc(2026, 11, 21, 18), settings: nashville), isTrue, reason: 'noon in Nashville');
      expect(pipSleepy(now: DateTime.utc(2026, 11, 22, 3), settings: nashville), isFalse, reason: '9 PM');
    });
    test('sleepy in their quiet hours, even after dark', () {
      final night = DateTime.utc(2026, 11, 22, 3);
      final l = night.toLocal();
      final m = l.hour * 60 + l.minute;
      final quiet = nashville.copyWith(quietHours: QuietHours(startMinute: (m - 30) % 1440, endMinute: (m + 30) % 1440));
      expect(pipSleepy(now: night, settings: quiet), isTrue);
    });
    test('no place yet: never sleepy', () {
      expect(pipSleepy(now: DateTime.utc(2026, 11, 21, 18), settings: const LookUpSettings()), isFalse);
    });
  });

  group('how Pip feels about a catch', () {
    final at = DateTime.utc(2026, 11, 2, 23);
    CatchMoment moment(List<Sighting> all, String id) =>
        CatchMoment.of(log: SkyLog.from(all), eventId: id, upcoming: const [], now: at, isPlus: false)!;
    Sighting s(String id, int day, {int hour = 23}) =>
        Sighting(eventId: id, seen: true, at: DateTime.utc(2026, 11, day, hour), type: SkyEventType.planetHighlight);

    test('amazed by a first catch', () => expect(caughtMood(moment([s('planet-a', 2)], 'planet-a')), PipMood.amazed));
    test('happy after that', () => expect(caughtMood(moment([s('planet-a', 2), s('planet-b', 4)], 'planet-b')), PipMood.happy));
    test('a wink for a secret found', () {
      // Two different things on one night: the Double night secret.
      final m = moment([s('planet-a', 2, hour: 20), s('planet-b', 2, hour: 22)], 'planet-b');
      expect(caughtMood(m), PipMood.wink);
    });
  });
}

String _key(PipEyes e) =>
    [e.lid, e.slant, e.smileL, e.smileR, e.sizeL, e.sizeR, e.glint, e.lookX, e.lookY, e.tilt, e.size].join(',');
