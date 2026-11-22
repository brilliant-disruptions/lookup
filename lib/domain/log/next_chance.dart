/// A badge's next real chance: the soonest coming event that would earn
/// it (or its next level). Shown on the patch; it never sends anything of
/// its own. Null when nothing coming would do it (an aurora, say, which
/// can't be known ahead: Pip taps them when it's up).
library;

import '../models/sky_event.dart';
import 'sky_log.dart';

SkyEvent? nextChance(Badge b, Iterable<SkyEvent> upcoming, DateTime now) {
  if (b.hidden) return null; // secrets stay secret
  if (b.earned && b.progress == null) return null; // nothing left to earn
  final u = now.toUtc();
  bool pass(SkyEvent e) => e.type == SkyEventType.iss || e.type == SkyEventType.tiangong || e.type == SkyEventType.starlinkTrain;
  bool fits(SkyEvent e) => switch (b.id) {
        'first-light' || 'regular' => true,
        'station-spotter' => e.type == SkyEventType.iss,
        'planet-set' => e.type == SkyEventType.planetHighlight &&
            (b.slots ?? const []).any((s) => !s.got && e.id.startsWith('planet-${s.label.toLowerCase()}')),
        'moon-phases' => (e.type == SkyEventType.fullMoonRise && (b.slots ?? const []).any((s) => s.label == 'Full' && !s.got)) ||
            (e.type == SkyEventType.moonPhase && (b.slots ?? const []).any((s) => s.label == 'Half' && !s.got)),
        'overhead' => pass(e) && e.peakElevationDeg >= 75,
        'venus-bright' => ((e.details['magnitude'] as num?)?.toDouble() ?? 99) <= -3.5,
        'train-spotter' => e.type == SkyEventType.starlinkTrain,
        'aurora-chaser' => e.type == SkyEventType.auroraNow,
        'meteor-watcher' => e.type == SkyEventType.meteorShower,
        'eclipse' => e.type == SkyEventType.lunarEclipse,
        'shadow' => e.type == SkyEventType.solarEclipse,
        'liftoff' => e.type == SkyEventType.rocketLaunch,
        'both-stations' => e.type == SkyEventType.tiangong || e.type == SkyEventType.iss,
        'night-owl' => e.peak.toLocal().hour < 4,
        'transit' => e.type == SkyEventType.issTransit,
        final id when id.startsWith('season-') => e.type == SkyEventType.meteorShower && id == _seasonId(e),
        _ => false,
      };
  final ahead = [
    for (final e in upcoming)
      if (e.end.isAfter(u) && e.details['past'] != true && (e.type.pushes || e.type == SkyEventType.issTransit) && fits(e)) e,
  ]..sort((a, b) => a.peak.compareTo(b.peak));
  return ahead.firstOrNull;
}

String? _seasonId(SkyEvent e) {
  final m = RegExp(r'^meteor-([A-Z]+):(\d{4})').firstMatch(e.id);
  return m == null ? null : 'season-${m.group(1)}-${m.group(2)}';
}
