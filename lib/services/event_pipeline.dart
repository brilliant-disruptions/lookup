/// Cached data in → the next week of [SkyEvent]s out. Pure Dart, testable.
library;

import '../data/local_store.dart';
import '../domain/aurora/aurora_rules.dart';
import '../domain/models/settings.dart';
import '../domain/models/sky_event.dart';
import '../domain/orbit/omm.dart';
import '../domain/passes/pass_predictor.dart';
import '../domain/starlink/train_detector.dart';
import '../domain/weather/cloud_forecast.dart';

class PipelineInputs {
  const PipelineInputs({
    required this.settings,
    required this.now,
    this.iss,
    this.tiangong,
    this.starlink,
    this.clouds,
    this.aurora,
  });

  final LookUpSettings settings;
  final DateTime now;
  final List<OmmRecord>? iss;
  final List<OmmRecord>? tiangong;
  final List<OmmRecord>? starlink;
  final CloudForecast? clouds;
  final AuroraSnapshot? aurora;
}

class EventPipeline {
  const EventPipeline({this.horizon = const Duration(days: 7), this.maxTrains = 3});

  final Duration horizon;
  final int maxTrains;

  List<SkyEvent> build(PipelineInputs i) {
    final s = i.settings;
    if (!s.hasLocation) return const [];
    final lat = s.latitude!, lon = s.longitude!;
    final now = i.now.toUtc();
    final to = now.add(horizon);
    final predictor = PassPredictor(latitude: lat, longitude: lon);
    final out = <SkyEvent>[];

    void passesFor(List<OmmRecord>? recs, SkyEventType type, double minPeak) {
      final r = recs?.where((r) => r.meanMotion > 0).firstOrNull;
      if (r == null) return;
      out.addAll(predictor.predict(
        record: r,
        type: type,
        from: now,
        to: to,
        minPeakElevationDeg: minPeak,
        clouds: i.clouds,
      ));
    }

    passesFor(i.iss, SkyEventType.iss, s.minIssPeakElevationDeg);
    if (s.tiangongEnabled) {
      passesFor(i.tiangong, SkyEventType.tiangong, s.minIssPeakElevationDeg);
    }

    if (i.starlink != null) {
      for (final g in TrainDetector.detect(i.starlink!).take(maxTrains)) {
        out.addAll(predictor.predict(
          record: g.representative,
          type: SkyEventType.starlinkTrain,
          from: now,
          to: to,
          minPeakElevationDeg: s.minStarlinkPeakElevationDeg,
          clouds: i.clouds,
          idPrefix: 'starlink-${g.launchKey}',
          details: {
            'count': g.count,
            'label': g.label,
            'launch': g.launchKey,
            'spreadMinutes': g.spreadDuration.inMinutes,
            'tight': g.isTight,
          },
        ));
      }
    }

    final a = i.aurora;
    if (a != null) {
      final outlook = auroraOutlook(
          now: now, latDeg: lat, lonDeg: lon, forecast: a.forecast);
      final w = outlook.window;
      if (w != null && outlook.level.index >= AuroraOutlookLevel.possible.index) {
        final mid = w.start.add(Duration(
            microseconds: w.end.difference(w.start).inMicroseconds ~/ 2));
        out.add(SkyEvent(
          id: 'aurora-outlook:${_minuteKey(w.start)}',
          type: SkyEventType.auroraOutlook,
          start: w.start,
          peak: mid,
          end: w.end,
          peakElevationDeg: 15,
          riseAzimuthDeg: 0,
          peakAzimuthDeg: 0,
          setAzimuthDeg: 0,
          cloudCoverPercent: i.clouds?.coverAt(mid),
          details: {
            'kp': outlook.maxKpTonight,
            'kpNeeded': double.parse(outlook.kpNeeded.toStringAsFixed(1)),
            'level': outlook.level.name,
            'headline': outlook.headline,
          },
        ));
      }
      final kpNow = a.kpNow;
      if (kpNow != null && s.auroraEnabled) {
        final d = auroraNow(
          now: now,
          latDeg: lat,
          lonDeg: lon,
          estimatedKp: kpNow,
          ovationProbability: a.ovationProbability,
          cloudCoverPercent: i.clouds?.coverAt(now),
        );
        if (d.alert) {
          // Bucketed to 3 h so repeated refreshes don't re-fire.
          final bucket = DateTime.utc(now.year, now.month, now.day, now.hour ~/ 3 * 3);
          out.add(SkyEvent(
            id: 'aurora-now:${_minuteKey(bucket)}',
            type: SkyEventType.auroraNow,
            start: now,
            peak: now,
            end: now.add(const Duration(hours: 3)),
            peakElevationDeg: 15,
            riseAzimuthDeg: 0,
            peakAzimuthDeg: 0,
            setAzimuthDeg: 0,
            cloudCoverPercent: i.clouds?.coverAt(now),
            details: {
              'kp': kpNow,
              'ovation': a.ovationProbability,
            },
          ));
        }
      }
    }

    out.removeWhere((e) => !e.end.isAfter(now));
    out.sort((x, y) => x.start.compareTo(y.start));
    return out;
  }

  static String _minuteKey(DateTime utc) {
    final t = utc.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}T${two(t.hour)}${two(t.minute)}Z';
  }
}
