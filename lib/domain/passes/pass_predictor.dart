/// Satellite pass → [SkyEvent]. Thin, testable layer over `satellite_observer`.
library;

import 'package:satellite_observer/satellite_observer.dart';

import '../models/sky_event.dart';
import '../orbit/omm.dart';
import '../weather/cloud_forecast.dart';

class PassPredictor {
  PassPredictor({required double latitude, required double longitude,
      double altitudeMeters = 0})
      : observer = Observer(
          latitudeDeg: latitude,
          longitudeDeg: longitude,
          altitudeMeters: altitudeMeters,
        );

  final Observer observer;

  /// Elements older than this at event time make the event an "estimate".
  static const maxElementAge = Duration(days: 5);

  /// Alert-worthy visible passes of one object in `[from, to]`.
  ///
  /// A pass qualifies when the observer is in civil darkness, the satellite
  /// is sunlit, its peak visible elevation ≥ [minPeakElevationDeg] and the
  /// visible arc lasts ≥ [minVisible].
  List<SkyEvent> predict({
    required OmmRecord record,
    required SkyEventType type,
    required DateTime from,
    required DateTime to,
    required double minPeakElevationDeg,
    Duration minVisible = const Duration(seconds: 60),
    CloudForecast? clouds,
    Map<String, Object?> details = const {},
    String? idPrefix,
  }) {
    final sat = SatelliteObserver(
      elements: record.toElements(),
      observer: observer,
    );
    final found = sat.visiblePasses(
      from: from.toUtc(),
      to: to.toUtc(),
      minElevationDeg: 10,
      twilight: TwilightPhase.civil,
    );
    final events = <SkyEvent>[];
    for (final pv in found) {
      if (!pv.isVisible || pv.visibleIntervals.isEmpty) continue;
      final intervals = pv.visibleIntervals;
      final start = intervals.first.startUtc;
      final end = intervals.last.endUtc;
      if (end.difference(start) < minVisible) continue;
      var peakLook = intervals.first.peakLookAngle;
      for (final iv in intervals.skip(1)) {
        if (iv.peakLookAngle.elevationDeg > peakLook.elevationDeg) {
          peakLook = iv.peakLookAngle;
        }
      }
      if (peakLook.elevationDeg < minPeakElevationDeg) continue;
      final riseLook = sat.lookAngleAt(start);
      final setLook = sat.lookAngleAt(end);
      final key = '${idPrefix ?? type.name}:${_minuteKey(peakLook.utc)}';
      events.add(SkyEvent(
        id: key,
        type: type,
        start: start,
        peak: peakLook.utc,
        end: end,
        peakElevationDeg: peakLook.elevationDeg,
        riseAzimuthDeg: riseLook.azimuthDeg,
        peakAzimuthDeg: peakLook.azimuthDeg,
        setAzimuthDeg: setLook.azimuthDeg,
        cloudCoverPercent: clouds?.coverAt(peakLook.utc),
        isEstimate: peakLook.utc.difference(record.epoch) > maxElementAge,
        details: {
          'object': record.objectName,
          'noradId': record.noradCatId,
          'rangeKm': peakLook.rangeKm.round(),
          'brightness': brightnessWord(
              rangeKm: peakLook.rangeKm, elevationDeg: peakLook.elevationDeg),
          ...details,
        },
      ));
    }
    return events;
  }

  static String _minuteKey(DateTime utc) {
    final t = utc.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}T${two(t.hour)}${two(t.minute)}Z';
  }
}

/// Crude but honest brightness words for a large sunlit object like the ISS.
/// Phase angle is ignored; range dominates for the passes we alert on.
String brightnessWord({required double rangeKm, required double elevationDeg}) {
  if (rangeKm < 600 && elevationDeg >= 50) return 'brighter than any star';
  if (rangeKm < 900) return 'as bright as the brightest stars';
  return 'bright, like a steady moving star';
}
