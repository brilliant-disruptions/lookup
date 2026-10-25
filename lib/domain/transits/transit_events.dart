/// [Transit]s as [SkyEvent]s for the Upcoming list.
library;

import '../models/sky_event.dart';
import '../orbit/omm.dart';
import '../weather/cloud_forecast.dart';
import 'transit_finder.dart';

List<SkyEvent> transitEvents({
  required OmmRecord record,
  required double latDeg,
  required double lonDeg,
  required DateTime from,
  required DateTime to,
  CloudForecast? clouds,
  double maxTravelKm = 50,
}) {
  final found = TransitFinder(record: record, maxTravelKm: maxTravelKm)
      .find(latDeg: latDeg, lonDeg: lonDeg, from: from, to: to);
  return [
    for (final t in found)
      SkyEvent(
        id: 'transit-${t.body.name}:${_secondKey(t.time)}',
        type: SkyEventType.issTransit,
        start: t.time.subtract(t.crossing ~/ 2),
        peak: t.time,
        end: t.time.add(t.crossing ~/ 2),
        peakElevationDeg: t.bodyAltitudeDeg,
        riseAzimuthDeg: t.bodyAzimuthDeg,
        peakAzimuthDeg: t.bodyAzimuthDeg,
        setAzimuthDeg: t.bodyAzimuthDeg,
        cloudCoverPercent: clouds?.coverAt(t.time),
        isEstimate: t.time.difference(record.epoch) > const Duration(days: 2),
        details: {
          'body': t.body.label,
          'crossingMs': t.crossing.inMilliseconds,
          'travelKm': double.parse(t.travelKm.toStringAsFixed(1)),
          'travelBearingDeg': t.travelBearingDeg.round(),
          'halfWidthKm': double.parse(t.halfWidthKm.toStringAsFixed(1)),
          'siteLat': double.parse(t.siteLat.toStringAsFixed(4)),
          'siteLon': double.parse(t.siteLon.toStringAsFixed(4)),
          'rangeKm': t.rangeKm.round(),
          'visibleHere': t.visibleHere,
        },
      ),
  ];
}

String _secondKey(DateTime utc) {
  final t = utc.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}${two(t.month)}${two(t.day)}T${two(t.hour)}${two(t.minute)}${two(t.second)}Z';
}
