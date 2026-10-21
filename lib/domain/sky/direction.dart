/// Azimuth / elevation → plain English. The notification never shows numbers.
library;

const _points = [
  'north', 'north-northeast', 'northeast', 'east-northeast',
  'east', 'east-southeast', 'southeast', 'south-southeast',
  'south', 'south-southwest', 'southwest', 'west-southwest',
  'west', 'west-northwest', 'northwest', 'north-northwest',
];

const _abbrev = [
  'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
  'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW',
];

int _index16(double azimuthDeg) {
  final a = ((azimuthDeg % 360) + 360) % 360;
  return ((a + 11.25) ~/ 22.5) % 16;
}

/// 16-point compass word, e.g. `west-southwest`.
String compassWord(double azimuthDeg) => _points[_index16(azimuthDeg)];

/// 16-point compass abbreviation, e.g. `WSW`.
String compassAbbrev(double azimuthDeg) => _abbrev[_index16(azimuthDeg)];

/// Elevation band in words.
String elevationWord(double elevationDeg) {
  if (elevationDeg >= 75) return 'straight overhead';
  if (elevationDeg >= 50) return 'high in the sky';
  if (elevationDeg >= 20) return 'about halfway up';
  return 'low on the horizon';
}

/// `4 min`, `90 sec`.
String durationWord(Duration d) {
  if (d.inSeconds < 100) return '${d.inSeconds} sec';
  final m = (d.inSeconds / 60).round();
  return '$m min';
}

/// "rising in the west-southwest, about halfway up at its best, 4 min"
String describeArc({
  required double riseAzimuthDeg,
  required double peakElevationDeg,
  required Duration duration,
}) =>
    'rising in the ${compassWord(riseAzimuthDeg)}, '
    '${elevationWord(peakElevationDeg)} at its best, '
    '${durationWord(duration)}';
