/// Dates as people wrote them. Dart's DateTime is Gregorian all the way back,
/// but history isn't: before 15 October 1582 dates are Julian (29 Feb 1504
/// is the night of Columbus' eclipse, not Gregorian 10 March), and there's
/// no year 0. Inside, years are astronomical (0 = 1 BC, −1 = 2 BC).
library;

/// Julian Day (days since noon, 1 Jan 4713 BC) for a moment.
double julianDayOf(DateTime utc) => utc.toUtc().millisecondsSinceEpoch / 86400000.0 + 2440587.5;

DateTime utcFromJulianDay(double jd) =>
    DateTime.fromMillisecondsSinceEpoch(((jd - 2440587.5) * 86400000).round(), isUtc: true);

/// True for dates written in the Julian calendar (before 15 Oct 1582).
bool isJulianDate(int year, int month, int day) =>
    year < 1582 || (year == 1582 && (month < 10 || (month == 10 && day < 15)));

/// The ten days Pope Gregory dropped: 5–14 October 1582 never happened.
bool isMissingDate(int year, int month, int day) => year == 1582 && month == 10 && day > 4 && day < 15;

int daysInMonth(int year, int month) {
  const days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (month != 2) return days[month - 1];
  final leap = year < 1583 ? year % 4 == 0 : (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0));
  return leap ? 29 : 28;
}

/// Julian Day at [hours] (0–24, UT or any clock) on a calendar date
/// (Meeus 7.1): Julian before the reform, Gregorian after.
double julianDay(int year, int month, int day, [double hours = 0]) {
  var y = year, m = month;
  if (m <= 2) {
    y -= 1;
    m += 12;
  }
  final a = (y / 100).floor();
  final b = isJulianDate(year, month, day) ? 0 : 2 - a + (a / 4).floor();
  return (365.25 * (y + 4716)).floor() + (30.6001 * (m + 1)).floor() + day + b - 1524.5 + hours / 24;
}

/// A calendar date and clock time, as written at the time.
class HistoricDate {
  const HistoricDate(this.year, this.month, this.day, this.hour, this.minute);
  final int year, month, day, hour, minute;

  /// From a Julian Day (Meeus 7.3).
  factory HistoricDate.fromJulianDay(double jd) {
    // Round to the minute first so 19:59:59.9 doesn't read 19:59.
    final j = (jd * 1440).round() / 1440;
    final z = (j + 0.5).floor();
    final f = j + 0.5 - z;
    var a = z;
    if (z >= 2299161) {
      final alpha = ((z - 1867216.25) / 36524.25).floor();
      a = z + 1 + alpha - (alpha / 4).floor();
    }
    final b = a + 1524;
    final c = ((b - 122.1) / 365.25).floor();
    final d = (365.25 * c).floor();
    final e = ((b - d) / 30.6001).floor();
    final day = b - d - (30.6001 * e).floor();
    final month = e < 14 ? e - 1 : e - 13;
    final year = month > 2 ? c - 4716 : c - 4715;
    final minutes = (f * 1440).round();
    return HistoricDate(year, month, day, minutes ~/ 60, minutes % 60);
  }

  /// "1504", "2 BC".
  String get yearLabel => year > 0 ? '$year' : '${1 - year} BC';

  /// "Feb 29, 1504".
  String get dateLabel => '${_months[month - 1]} $day, $yearLabel';

  /// "7:30 PM".
  String get timeLabel {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    return '$h:${minute.toString().padLeft(2, '0')} ${hour < 12 ? 'AM' : 'PM'}';
  }
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Local mean time at a longitude: the clock the Sun keeps there. Before
/// time zones (and for any year before 1900) that's what "9 PM" meant.
HistoricDate localMeanTime(DateTime utc, double lonDeg) => HistoricDate.fromJulianDay(julianDayOf(utc) + lonDeg / 360);

/// The moment at [hours] local mean time on a calendar date at [lonDeg].
DateTime utcFromLocalMeanTime(int year, int month, int day, double hours, double lonDeg) =>
    utcFromJulianDay(julianDay(year, month, day, hours) - lonDeg / 360);
