/// What a free user really missed: Plus-only sights from the last week that
/// were genuinely there to see. Cloud cover has to be known and low; an
/// unknown sky never counts, so the app never claims a miss it can't back.
library;

import '../models/sky_event.dart';

/// Newest first, as [recent] is.
List<SkyEvent> missedWithoutPlus(Iterable<SkyEvent> recent, {int maxCloudPercent = 40}) => [
      for (final e in recent)
        if (e.plusOnly && e.type.pushes && e.cloudCoverPercent != null && e.cloudCoverPercent! <= maxCloudPercent) e,
    ];
