/// Equinoxes and solstices: the instants the Sun reaches 0°, 90°, 180° and
/// 270° of apparent longitude. Meeus, Astronomical Algorithms ch. 27
/// (mean instants for 2000–3000 plus the 24 periodic terms), good to about
/// a minute; test/domain/seasons_test.dart pins USNO's published times.
library;

import 'dart:math' as math;

import 'delta_t.dart';

enum SeasonMark {
  marchEquinox,
  juneSolstice,
  septemberEquinox,
  decemberSolstice;

  bool get equinox => this == marchEquinox || this == septemberEquinox;
}

class SeasonStart {
  const SeasonStart(this.mark, this.at);
  final SeasonMark mark;

  /// UTC.
  final DateTime at;
}

const _jde0 = <List<double>>[
  [2451623.80984, 365242.37404, 0.05169, -0.00411, -0.00057],
  [2451716.56767, 365241.62603, 0.00325, 0.00888, -0.00030],
  [2451810.21715, 365242.01767, -0.11575, 0.00337, 0.00078],
  [2451900.05952, 365242.74049, -0.06223, -0.00823, 0.00032],
];

const _terms = <List<double>>[
  [485, 324.96, 1934.136], [203, 337.23, 32964.467], [199, 342.08, 20.186], [182, 27.85, 445267.112],
  [156, 73.14, 45036.886], [136, 171.52, 22518.443], [77, 222.54, 65928.934], [74, 296.72, 3034.906],
  [70, 243.58, 9037.513], [58, 119.81, 33718.147], [52, 297.17, 150.678], [50, 21.02, 2281.226],
  [45, 247.54, 29929.562], [44, 325.15, 31555.956], [29, 60.93, 4443.417], [18, 155.12, 67555.328],
  [17, 288.79, 4562.452], [16, 198.04, 62894.029], [14, 199.76, 31436.921], [12, 95.39, 14577.848],
  [12, 287.11, 31931.756], [12, 320.81, 34777.259], [9, 227.73, 1222.114], [8, 15.45, 16859.074],
];

double _cosd(double d) => math.cos(d * math.pi / 180);

/// The instant of [mark] in [year] (2000–3000), UTC.
DateTime seasonStart(int year, SeasonMark mark) {
  final y = (year - 2000) / 1000;
  final c = _jde0[mark.index];
  final jde0 = c[0] + c[1] * y + c[2] * y * y + c[3] * y * y * y + c[4] * y * y * y * y;
  final t = (jde0 - 2451545.0) / 36525;
  final w = 35999.373 * t - 2.47;
  final dl = 1 + 0.0334 * _cosd(w) + 0.0007 * _cosd(2 * w);
  var s = 0.0;
  for (final k in _terms) {
    s += k[0] * _cosd(k[1] + k[2] * t);
  }
  final jde = jde0 + 0.00001 * s / dl;
  final tt = DateTime.utc(2000, 1, 1, 12).add(Duration(milliseconds: ((jde - 2451545.0) * 86400000).round()));
  return tt.subtract(Duration(milliseconds: (deltaTSeconds(year + (mark.index * 3 + 2.7) / 12) * 1000).round()));
}

/// Every equinox and solstice in [from, to), in order.
List<SeasonStart> seasonsBetween(DateTime from, DateTime to) {
  final out = <SeasonStart>[];
  for (var y = from.toUtc().year; y <= to.toUtc().year; y++) {
    for (final m in SeasonMark.values) {
      final at = seasonStart(y, m);
      if (!at.isBefore(from.toUtc()) && at.isBefore(to.toUtc())) out.add(SeasonStart(m, at));
    }
  }
  return out;
}

/// Its name where you are: the March equinox starts spring in the north and
/// autumn in the south.
String seasonName(SeasonMark m, {required double latDeg}) {
  final north = latDeg >= 0;
  return switch (m) {
    SeasonMark.marchEquinox => north ? 'Spring equinox' : 'Autumn equinox',
    SeasonMark.juneSolstice => north ? 'Summer solstice' : 'Winter solstice',
    SeasonMark.septemberEquinox => north ? 'Autumn equinox' : 'Spring equinox',
    SeasonMark.decemberSolstice => north ? 'Winter solstice' : 'Summer solstice',
  };
}

/// One plain line about it, in words.
String seasonLine(SeasonMark m, {required double latDeg}) {
  final north = latDeg >= 0;
  return switch (m) {
    SeasonMark.marchEquinox || SeasonMark.septemberEquinox =>
      'Day and night about the same length everywhere. The Sun rises due east and sets due west.',
    SeasonMark.juneSolstice => north
        ? 'The longest day of the year, and the shortest night.'
        : 'The shortest day of the year, and the longest night: the most dark sky.',
    SeasonMark.decemberSolstice => north
        ? 'The shortest day of the year, and the longest night: the most dark sky.'
        : 'The longest day of the year, and the shortest night.',
  };
}
