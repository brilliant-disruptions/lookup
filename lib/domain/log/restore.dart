/// Bringing the Log back on a new phone: every catch went into the LookUp
/// album with its sighting written into the file (`CatchTag`). With iCloud
/// Photos (or Google Photos) the album comes back; this turns what's found
/// in it into sightings the Log doesn't already have. Pure.
library;

import '../models/sky_event.dart';
import '../photo/catch_tag.dart';
import 'sighting.dart';

/// One picture found in the album, read back.
typedef FoundCatch = ({String assetId, CatchTag tag});

/// The sightings to add: one per sighting id not already in [have] (the
/// earliest picture of it when there are several), oldest first.
List<({Sighting sighting, String assetId})> restorable(Iterable<FoundCatch> found, Set<String> have) {
  final best = <String, FoundCatch>{};
  for (final f in found) {
    final id = f.tag.eventId;
    if (have.contains(id)) continue;
    final b = best[id];
    if (b == null || f.tag.at.isBefore(b.tag.at)) best[id] = f;
  }
  final out = [
    for (final f in best.values)
      (
        sighting: Sighting(
          eventId: f.tag.eventId,
          seen: true,
          at: f.tag.at,
          eventTime: f.tag.at,
          type: SkyEventType.values.where((t) => t.name == f.tag.type).firstOrNull,
          peakElevationDeg: f.tag.elevationDeg,
          magnitude: f.tag.magnitude,
          place: f.tag.place,
        ),
        assetId: f.assetId,
      ),
  ]..sort((a, b) => a.sighting.at.compareTo(b.sighting.at));
  return out;
}
