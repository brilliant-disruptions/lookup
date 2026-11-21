/// The hours a day bar shows (pure maths, no Flutter).
///
/// Every row on the Week tab is one calendar day, midnight to midnight. Most
/// of a day has nothing on, so the hours nobody has anything in are chopped
/// out: the bar shows only the hours around a sight (an hour either side),
/// with a narrow break where time was cut. One axis serves every day, so
/// the rows stay lined up on the clock.
library;

/// A run of hours that is shown: `from` up to (not including) `to`, 0 to 24.
typedef HourRun = ({int from, int to});

/// Local hour of day for [t], with minutes as a fraction (18:30 is 18.5).
double hourOfDay(DateTime t) {
  final l = t.toLocal();
  return l.hour + l.minute / 60 + l.second / 3600;
}

class DayAxis {
  const DayAxis(this.runs);

  /// The hours around each start (`pad` either side), joined into runs. With
  /// nothing on at all, the evening.
  factory DayAxis.forStarts(Iterable<DateTime> starts, {int pad = 1}) {
    final keep = List<bool>.filled(24, false);
    for (final t in starts) {
      final h = t.toLocal().hour;
      for (var k = h - pad; k <= h + pad; k++) {
        if (k >= 0 && k < 24) keep[k] = true;
      }
    }
    if (!keep.contains(true)) {
      for (var k = 20; k < 24; k++) {
        keep[k] = true;
      }
    }
    final runs = <HourRun>[];
    int? from;
    for (var h = 0; h <= 24; h++) {
      final on = h < 24 && keep[h];
      if (on && from == null) from = h;
      if (!on && from != null) {
        runs.add((from: from, to: h));
        from = null;
      }
    }
    return DayAxis(runs);
  }

  final List<HourRun> runs;

  int get keptHours => runs.fold(0, (a, r) => a + r.to - r.from);

  bool keeps(int hour) => runs.any((r) => hour >= r.from && hour < r.to);

  /// Breaks where time was cut: between runs, and at either end of the day
  /// if it doesn't start or end shown.
  int get breakCount => runs.length - 1 + (runs.first.from > 0 ? 1 : 0) + (runs.last.to < 24 ? 1 : 0);

  double _lead(double breakPx) => runs.first.from > 0 ? breakPx : 0;

  /// Total width with each shown hour [perHour] wide and each break [breakPx].
  double width(double perHour, double breakPx) => keptHours * perHour + breakCount * breakPx;

  /// Where [hour] (0 to 24, fractional) falls along the bar. An hour that
  /// was cut lands in the middle of the break that replaced it.
  double x(double hour, double perHour, double breakPx) {
    var pos = _lead(breakPx);
    if (hour < runs.first.from) return pos / 2;
    for (var i = 0; i < runs.length; i++) {
      final r = runs[i];
      if (hour < r.from) return pos - breakPx / 2;
      if (hour <= r.to) return pos + (hour - r.from) * perHour;
      pos += (r.to - r.from) * perHour;
      if (i < runs.length - 1 || r.to < 24) pos += breakPx;
    }
    return pos - breakPx / 2;
  }

  /// The breaks as (left, width) boxes along the bar.
  List<(double, double)> breaks(double perHour, double breakPx) {
    final out = <(double, double)>[];
    var pos = 0.0;
    if (runs.first.from > 0) {
      out.add((0, breakPx));
      pos = breakPx;
    }
    for (var i = 0; i < runs.length; i++) {
      pos += (runs[i].to - runs[i].from) * perHour;
      if (i < runs.length - 1 || runs[i].to < 24) {
        out.add((pos, breakPx));
        pos += breakPx;
      }
    }
    return out;
  }
}
