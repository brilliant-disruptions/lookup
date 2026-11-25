import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/sky/seasons.dart';

void main() {
  // USNO, Earth's Seasons (aa.usno.navy.mil/data/Earth_Seasons), UTC to the minute.
  final usno = {
    (2024, SeasonMark.marchEquinox): DateTime.utc(2024, 3, 20, 3, 6),
    (2024, SeasonMark.juneSolstice): DateTime.utc(2024, 6, 20, 20, 51),
    (2024, SeasonMark.septemberEquinox): DateTime.utc(2024, 9, 22, 12, 44),
    (2024, SeasonMark.decemberSolstice): DateTime.utc(2024, 12, 21, 9, 21),
    (2026, SeasonMark.marchEquinox): DateTime.utc(2026, 3, 20, 14, 46),
    (2026, SeasonMark.juneSolstice): DateTime.utc(2026, 6, 21, 8, 24),
    (2026, SeasonMark.septemberEquinox): DateTime.utc(2026, 9, 23, 0, 5),
    (2026, SeasonMark.decemberSolstice): DateTime.utc(2026, 12, 21, 20, 50),
  };

  for (final e in usno.entries) {
    test('${e.key.$2.name} ${e.key.$1} within 2 minutes of USNO', () {
      final got = seasonStart(e.key.$1, e.key.$2);
      expect(got.difference(e.value).inSeconds.abs(), lessThan(120), reason: '$got');
    });
  }

  test('a year has four, in order', () {
    final s = seasonsBetween(DateTime.utc(2026, 11, 25), DateTime.utc(2027, 11, 25));
    expect(s.map((x) => x.mark), [
      SeasonMark.decemberSolstice,
      SeasonMark.marchEquinox,
      SeasonMark.juneSolstice,
      SeasonMark.septemberEquinox,
    ]);
  });

  test('named for the hemisphere', () {
    expect(seasonName(SeasonMark.decemberSolstice, latDeg: 40), 'Winter solstice');
    expect(seasonName(SeasonMark.decemberSolstice, latDeg: -34), 'Summer solstice');
    expect(seasonName(SeasonMark.marchEquinox, latDeg: -34), 'Autumn equinox');
  });
}
