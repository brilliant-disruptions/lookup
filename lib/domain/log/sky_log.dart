/// The user's sky log: what they've seen, streaks, and badges.
library;

import '../models/sky_event.dart';
import 'sighting.dart';

class Badge {
  const Badge(this.id, this.title, this.description, {this.earnedAt});
  final String id;
  final String title;
  final String description;
  final DateTime? earnedAt;
  bool get earned => earnedAt != null;

  Badge earn(DateTime at) => Badge(id, title, description, earnedAt: at);
}

class SkyLog {
  SkyLog._({required this.seen, required this.counts, required this.badges, required this.hitRate});

  /// Seen events, newest first.
  final List<Sighting> seen;
  final Map<SkyEventType, int> counts;
  final List<Badge> badges;

  /// Share of answered alerts the user actually saw (null with < 3 answers).
  final double? hitRate;

  int get total => seen.length;
  int get earnedCount => badges.where((b) => b.earned).length;

  static const _defs = <Badge>[
    Badge('first-light', 'First light', 'Saw your first thing LookUp tapped you for.'),
    Badge('station-spotter', 'Station spotter', 'Saw the space station 5 times.'),
    Badge('regular', 'Regular', 'Saw 10 events.'),
    Badge('overhead', 'Straight overhead', 'Saw a pass that climbed above 75°.'),
    Badge('venus-bright', 'Venus-bright', 'Saw something as bright as Venus.'),
    Badge('train-spotter', 'Train spotter', 'Saw a Starlink train.'),
    Badge('aurora-chaser', 'Aurora chaser', 'Saw an aurora.'),
    Badge('meteor-watcher', 'Meteor watcher', 'Watched a meteor shower peak.'),
    Badge('eclipse', 'Blood moon', 'Watched a lunar eclipse.'),
    Badge('shadow', 'In the shadow', 'Watched a solar eclipse.'),
    Badge('liftoff', 'Liftoff', 'Watched a rocket launch.'),
    Badge('both-stations', 'Both stations', 'Saw the ISS and Tiangong.'),
    Badge('night-owl', 'Night owl', 'Saw something between midnight and 4 AM.'),
    Badge('transit', 'Silhouette', 'Caught the station crossing the Sun or Moon.'),
  ];

  factory SkyLog.from(List<Sighting> all) {
    final seen = [...all.where((s) => s.seen)]..sort((a, b) => b.at.compareTo(a.at));
    final counts = <SkyEventType, int>{};
    for (final s in seen) {
      final t = s.inferredType;
      if (t != null) counts[t] = (counts[t] ?? 0) + 1;
    }
    // Earned at the moment the condition first became true (chronological).
    final chrono = seen.reversed.toList();
    final earned = <String, DateTime>{};
    final running = <SkyEventType, int>{};
    for (var i = 0; i < chrono.length; i++) {
      final s = chrono[i];
      final t = s.inferredType;
      if (t != null) running[t] = (running[t] ?? 0) + 1;
      void give(String id, bool cond) {
        if (cond) earned.putIfAbsent(id, () => s.at);
      }

      final local = (s.eventTime ?? s.at).toLocal();
      give('first-light', true);
      give('station-spotter', (running[SkyEventType.iss] ?? 0) >= 5);
      give('regular', i + 1 >= 10);
      give('overhead', (s.peakElevationDeg ?? 0) >= 75 && (t == SkyEventType.iss || t == SkyEventType.tiangong || t == SkyEventType.starlinkTrain));
      give('venus-bright', (s.magnitude ?? 99) <= -3.5);
      give('train-spotter', t == SkyEventType.starlinkTrain);
      give('aurora-chaser', t == SkyEventType.auroraNow || t == SkyEventType.auroraOutlook);
      give('meteor-watcher', t == SkyEventType.meteorShower);
      give('eclipse', t == SkyEventType.lunarEclipse);
      give('shadow', t == SkyEventType.solarEclipse);
      give('liftoff', t == SkyEventType.rocketLaunch);
      give('both-stations', (running[SkyEventType.iss] ?? 0) > 0 && (running[SkyEventType.tiangong] ?? 0) > 0);
      give('night-owl', local.hour < 4);
      give('transit', t == SkyEventType.issTransit);
    }
    final badges = [for (final b in _defs) earned.containsKey(b.id) ? b.earn(earned[b.id]!) : b];
    final answered = all.length;
    return SkyLog._(
      seen: seen,
      counts: counts,
      badges: badges,
      hitRate: answered >= 3 ? seen.length / answered : null,
    );
  }
}
