/// "Can I actually see it?": altitude, brightness, twilight, moonlight, how
/// dark the user's sky is, and the weather, folded into one plain verdict.
library;

import '../weather/cloud_forecast.dart';
import 'astro.dart';
import 'sun.dart';

/// How dark the sky is where the user looks from (they pick it once).
enum SkyDarkness {
  city('City', 'Only the brightest stars', 3.0),
  suburbs('Suburbs', 'The main constellations', 4.5),
  dark('Dark sky', 'Countryside, the Milky Way shows', 6.0);

  const SkyDarkness(this.label, this.hint, this.limitMag);
  final String label;
  final String hint;

  /// Faintest star visible on a moonless night, overhead.
  final double limitMag;
}

double _moonIllum(DateTime utc) => moonIllumination(utc);

/// What the sky is doing at one moment.
class SkyConditions {
  const SkyConditions({
    required this.sunAltDeg,
    required this.moonAltDeg,
    required this.moonIllumination,
    this.cloudPercent,
    this.visibilityM,
    this.precipProbability,
  });
  final double sunAltDeg;
  final double moonAltDeg;
  final double moonIllumination;
  final int? cloudPercent;
  final int? visibilityM;
  final int? precipProbability;

  static SkyConditions at(DateTime utc, double lat, double lon, {CloudForecast? weather}) {
    final s = weather?.sampleAt(utc);
    return SkyConditions(
      sunAltDeg: sunAltitudeDeg(utc, lat, lon),
      moonAltDeg: moonHorizontal(utc, lat, lon).altitudeDeg,
      moonIllumination: _moonIllum(utc),
      cloudPercent: s?.coverPercent,
      visibilityM: s?.visibilityM,
      precipProbability: s?.precipProbability,
    );
  }

  /// Faintest point-source magnitude visible now, before the weather.
  double limitMag(SkyDarkness darkness, {bool diffuse = false}) {
    var limit = darkness.limitMag;
    if (sunAltDeg > 0) {
      limit = -3.5; // daylight: only Venus at its best
    } else if (sunAltDeg > -6) {
      limit = 0.5;
    } else if (sunAltDeg > -12) {
      limit = limit < 3.0 ? limit : 3.0;
    } else if (sunAltDeg > -18) {
      limit -= 0.7;
    }
    if (moonAltDeg > 0) limit -= moonIllumination * (diffuse ? 2.5 : 1.2);
    return limit;
  }
}

enum Seeability {
  great('Easy to see'),
  good('Visible'),
  low('Low: needs a clear view to the horizon'),
  patchy('Through gaps in the cloud'),
  cloudy('Hidden by cloud'),
  foggy('Too hazy'),
  rain('Rain likely'),
  moonlit('Washed out by the Moon'),
  twilight('Too light out still'),
  tooFaint('Too faint for your sky'),
  belowHorizon('Below the horizon');

  const Seeability(this.words);
  final String words;

  bool get yes => this == great || this == good || this == low || this == patchy;
}

/// [mag] is the object's brightness; [diffuse] objects (galaxies, nebulae,
/// the Milky Way) behave as if half a magnitude fainter and suffer more from
/// moonlight.
Seeability canSee({
  required double altDeg,
  required double mag,
  required SkyConditions c,
  required SkyDarkness darkness,
  bool diffuse = false,
}) {
  if (altDeg < 0) return Seeability.belowHorizon;
  final effective = mag + (diffuse ? 0.5 : 0.0);
  // Low objects fight extra air: ~0.5 mag dimmer near 10°.
  final extinction = altDeg < 20 ? (20 - altDeg) / 20 * 0.6 : 0.0;
  final limit = c.limitMag(darkness, diffuse: diffuse);
  if (effective + extinction > limit) {
    final moonless = SkyConditions(
      sunAltDeg: c.sunAltDeg,
      moonAltDeg: -10,
      moonIllumination: 0,
    ).limitMag(darkness, diffuse: diffuse);
    if (c.sunAltDeg > -12 && effective + extinction <= darkness.limitMag) return Seeability.twilight;
    if (c.moonAltDeg > 0 && effective + extinction <= moonless) return Seeability.moonlit;
    return Seeability.tooFaint;
  }
  final p = c.precipProbability;
  if (p != null && p >= 60) return Seeability.rain;
  final cloud = c.cloudPercent;
  if (cloud != null && cloud >= 75) return Seeability.cloudy;
  final vis = c.visibilityM;
  if (vis != null && vis < 4000) return Seeability.foggy;
  if (cloud != null && cloud > 40) return Seeability.patchy;
  if (altDeg < 12) return Seeability.low;
  return limit - (effective + extinction) > 1.5 ? Seeability.great : Seeability.good;
}

/// The sky itself at one moment, for looking ahead on the map: light and
/// weather first, in [canSee]'s order and thresholds. Never a promise that
/// anything in particular will show.
String skyWords(SkyConditions c) {
  if (c.sunAltDeg > 0) return 'Daylight';
  if (c.sunAltDeg > -6) return 'Twilight';
  final p = c.precipProbability;
  if (p != null && p >= 60) return 'Rain likely';
  final cloud = c.cloudPercent;
  if (cloud == null) return 'No cloud forecast for then';
  if (cloud >= 75) return 'Cloudy';
  final vis = c.visibilityM;
  if (vis != null && vis < 4000) return 'Hazy';
  if (cloud > 40) return 'Some cloud';
  if (c.sunAltDeg > -12) return 'Clear, not fully dark';
  return 'Clear';
}

/// Tonight's weather in one line and the best stretch to be out.
class NightOutlook {
  const NightOutlook({required this.start, required this.end, required this.hours, this.bestStart, this.bestEnd});
  final DateTime start;
  final DateTime end;

  /// One sample per hour across the dark window.
  final List<CloudSample> hours;
  final DateTime? bestStart;
  final DateTime? bestEnd;

  bool get hasForecast => hours.isNotEmpty;

  static bool _clear(CloudSample s) => s.coverPercent <= 30 && (s.precipProbability ?? 0) < 40;

  static NightOutlook from({required DateTime start, required DateTime end, CloudForecast? weather}) {
    final hours = <CloudSample>[];
    if (weather != null) {
      var t = DateTime.utc(start.year, start.month, start.day, start.hour);
      while (t.isBefore(end)) {
        final s = weather.sampleAt(t);
        if (s != null && !t.isBefore(start.subtract(const Duration(minutes: 59)))) hours.add(s);
        t = t.add(const Duration(hours: 1));
      }
    }
    // Longest run of clear hours.
    DateTime? bs, be;
    var runStart = -1, bestLen = 0;
    for (var i = 0; i <= hours.length; i++) {
      final clear = i < hours.length && _clear(hours[i]);
      if (clear && runStart < 0) runStart = i;
      if (!clear && runStart >= 0) {
        if (i - runStart > bestLen) {
          bestLen = i - runStart;
          bs = hours[runStart].time;
          be = hours[i - 1].time.add(const Duration(hours: 1));
        }
        runStart = -1;
      }
    }
    if (bs != null && bs.isBefore(start)) bs = start;
    if (be != null && be.isAfter(end)) be = end;
    return NightOutlook(start: start, end: end, hours: hours, bestStart: bs, bestEnd: be);
  }

  /// "clear" | "clouds-later" | "clearing" | "patchy" | "cloudy" | "unknown":
  /// the UI turns this and the times into words.
  String get shape {
    if (hours.isEmpty) return 'unknown';
    final clearCount = hours.where(_clear).length;
    if (clearCount == hours.length) return 'clear';
    if (clearCount == 0) {
      return hours.every((h) => h.coverPercent >= 75) ? 'cloudy' : 'patchy';
    }
    if (_clear(hours.first) && bestStart != null && !bestStart!.isAfter(hours.first.time.add(const Duration(minutes: 59)))) {
      return 'clouds-later';
    }
    if (_clear(hours.last)) return 'clearing';
    return 'patchy';
  }
}
