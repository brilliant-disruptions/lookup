/// Alerts that learn from "what got in the way?" answers.
///
/// Recent "no" answers nudge the user's thresholds so the next tap is more
/// likely to be worth it. Only recent answers count, so a cloudy month
/// doesn't make the app permanently timid. Bounded both ways.
library;

import '../log/sighting.dart';
import '../models/settings.dart';

class AlertTuning {
  const AlertTuning({this.cloudCutoffPercent = LookUpSettings.cloudyThresholdPercent, this.extraMinElevationDeg = 0, this.reasons = const []});

  /// Forecast cover above which an alert is suppressed (normally 60%).
  final int cloudCutoffPercent;

  /// Added to the per-type minimum peak elevation.
  final double extraMinElevationDeg;

  /// Human-readable reasons, shown in Settings ("Learned from you").
  final List<String> reasons;

  static const neutral = AlertTuning();

  bool get isNeutral => cloudCutoffPercent == LookUpSettings.cloudyThresholdPercent && extraMinElevationDeg == 0;

  /// Derive tuning from the last [window] answers (most recent first or not).
  factory AlertTuning.from(List<Sighting> sightings, {int window = 8, DateTime? now}) {
    final cutoff = (now ?? DateTime.now().toUtc()).subtract(const Duration(days: 60));
    final recent = [...sightings.where((s) => s.at.isAfter(cutoff))]..sort((a, b) => b.at.compareTo(a.at));
    final last = recent.take(window).toList();
    final clouds = last.where((s) => !s.seen && s.reason == 'clouds').length;
    final tooLow = last.where((s) => !s.seen && s.reason == 'too-low').length;
    final seenHigh = last.where((s) => s.seen && (s.peakElevationDeg ?? 90) < 35).length;

    var cloud = LookUpSettings.cloudyThresholdPercent;
    final reasons = <String>[];
    if (clouds >= 2) {
      cloud = clouds >= 4 ? 30 : 40;
      reasons.add('Clouds got in the way $clouds times, so we only tap when the forecast is under $cloud% cloud.');
    }
    var extra = 0.0;
    if (tooLow >= 2 && seenHigh == 0) {
      extra = tooLow >= 4 ? 20 : 10;
      reasons.add('Low passes were hard to see from your spot, so we skip ones that don\'t climb ${extra.round()}° higher.');
    }
    return AlertTuning(cloudCutoffPercent: cloud, extraMinElevationDeg: extra, reasons: reasons);
  }

  /// Settings with learned thresholds applied (never below the user's own).
  LookUpSettings apply(LookUpSettings s) => s.copyWith(
        minIssPeakElevationDeg: s.minIssPeakElevationDeg + extraMinElevationDeg,
        minStarlinkPeakElevationDeg: s.minStarlinkPeakElevationDeg + extraMinElevationDeg,
      );
}
