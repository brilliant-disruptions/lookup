/// Famous nights to visit on the sky map, each pinned in
/// test/domain/history_test.dart to what JPL Horizons shows from that place
/// at that moment, so none of them is a story the sky doesn't back up.
library;

import 'calendar.dart';

class FamousNight {
  const FamousNight({
    required this.id,
    required this.title,
    required this.blurb,
    required this.place,
    required this.lat,
    required this.lon,
    required this.year,
    required this.month,
    required this.day,
    required this.localHours,
    this.focus,
  });

  final String id;
  final String title;
  final String blurb;

  /// Where to stand: the map moves there for the visit.
  final String place;
  final double lat, lon;

  /// The date as written then (Julian before 1582) and local mean time.
  final int year, month, day;
  final double localHours;

  /// The thing to ring on the map, as a SkyId ("planet:jupiter", "moon"),
  /// or a star's name.
  final String? focus;

  DateTime get utc => utcFromLocalMeanTime(year, month, day, localHours, lon);
}

/// Oldest first.
const famousNights = <FamousNight>[
  FamousNight(
    id: 'giza',
    title: 'The pyramid builders\' pole star',
    blurb: 'Around 2560 BC, as the Great Pyramid went up, the star the sky turned round '
        'was Thuban in Draco, a degree from the pole. Polaris was just another star.',
    place: 'Giza',
    lat: 29.98,
    lon: 31.13,
    year: -2559,
    month: 3,
    day: 21,
    localHours: 21,
    focus: 'Thuban',
  ),
  FamousNight(
    id: 'conjunction-7bc',
    title: 'Jupiter and Saturn meet, 7 BC',
    blurb: 'Three times in 7 BC Jupiter passed Saturn, a degree apart each time, in Pisces. '
        'One of the favourite explanations for the Star of Bethlehem.',
    place: 'Jerusalem',
    lat: 31.78,
    lon: 35.23,
    year: -6,
    month: 10,
    day: 1,
    localHours: 21,
    focus: 'planet:jupiter',
  ),
  FamousNight(
    id: 'conjunction-2bc',
    title: 'Venus and Jupiter almost touch, 2 BC',
    blurb: 'On 17 June 2 BC the two brightest planets came within a fifth of a degree of each other, '
        'low in the west after sunset: to the eye, one brilliant star.',
    place: 'Jerusalem',
    lat: 31.78,
    lon: 35.23,
    year: -1,
    month: 6,
    day: 17,
    localHours: 19.75,
    focus: 'planet:venus',
  ),
  FamousNight(
    id: 'columbus',
    title: 'Columbus\' eclipse',
    blurb: 'Stranded on Jamaica, Columbus warned the islanders the Moon would lose its light. '
        'It rose eclipsed on 29 February 1504, as his almanac said it would.',
    place: 'Jamaica',
    lat: 18.45,
    lon: -77.20,
    year: 1504,
    month: 2,
    day: 29,
    localHours: 19.5,
    focus: 'moon',
  ),
  FamousNight(
    id: 'galileo',
    title: 'Galileo finds Jupiter\'s moons',
    blurb: 'On 7 January 1610 Galileo turned his new telescope on Jupiter, high in the east, '
        'and saw three little "stars" in a line beside it. Binoculars show them today.',
    place: 'Padua',
    lat: 45.41,
    lon: 11.88,
    year: 1610,
    month: 1,
    day: 7,
    localHours: 18,
    focus: 'planet:jupiter',
  ),
  FamousNight(
    id: 'titanic',
    title: 'The night the Titanic struck',
    blurb: 'Calm, clear and moonless: no moonlight on the water to show the iceberg, '
        'and no waves breaking at its foot. The Moon didn\'t rise until morning.',
    place: 'North Atlantic',
    lat: 41.73,
    lon: -49.95,
    year: 1912,
    month: 4,
    day: 14,
    localHours: 23.3033, // 11:40 PM ship's time (GMT − 2 h 58 min) = 2:38 GMT
  ),
  FamousNight(
    id: 'apollo11',
    title: 'The first step on the Moon',
    blurb: 'At 9:56 PM in Houston on 20 July 1969, Neil Armstrong stepped onto the Moon. '
        'It hung in the west-southwest, nearly half lit, for anyone outside to look up at.',
    place: 'Houston',
    lat: 29.55,
    lon: -95.10,
    year: 1969,
    month: 7,
    day: 20,
    localHours: 20.5933, // 9:56 PM CDT = 2:56 GMT
    focus: 'moon',
  ),
];
