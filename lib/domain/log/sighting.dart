/// One "did you see it?" answer, as the domain sees it.
library;

import '../models/sky_event.dart';

class Sighting {
  const Sighting({
    required this.eventId,
    required this.seen,
    required this.at,
    this.type,
    this.reason,
    this.eventTime,
    this.peakElevationDeg,
    this.magnitude,
    this.place,
    this.photo,
  });

  final String eventId;
  final bool seen;
  final DateTime at; // when answered
  final SkyEventType? type;
  final String? reason; // clouds | too-low | missed
  final DateTime? eventTime;
  final double? peakElevationDeg;
  final double? magnitude;
  final String? place;

  /// File name of the user's photo of it, if they added one.
  final String? photo;

  /// Older answers stored only the event id; infer the type from its prefix.
  SkyEventType? get inferredType {
    if (type != null) return type;
    final id = eventId;
    if (id.startsWith('iss:')) return SkyEventType.iss;
    if (id.startsWith('tiangong:')) return SkyEventType.tiangong;
    if (id.startsWith('starlink')) return SkyEventType.starlinkTrain;
    if (id.startsWith('aurora')) return SkyEventType.auroraNow;
    if (id.startsWith('meteor-')) return SkyEventType.meteorShower;
    if (id.startsWith('eclipse:')) return SkyEventType.lunarEclipse;
    if (id.startsWith('pair:')) return SkyEventType.planetPairing;
    if (id.startsWith('launch:')) return SkyEventType.rocketLaunch;
    if (id.startsWith('transit-')) return SkyEventType.issTransit;
    if (id.startsWith('sat:')) return SkyEventType.satellitePass;
    return null;
  }
}
