/// Finds Starlink launch groups that are still flying as a "train".
///
/// Heuristic (checked against the live catalog on 2026-10-21): a launch group
/// is in train phase while its satellites are still in the low parking orbit
/// (mean motion ≥ 15.6 rev/day) and have completed ≤ 500 revolutions. Tight,
/// dramatic trains are ≤ 150 revolutions (~10 days).
library;

import '../orbit/omm.dart';

class StarlinkLaunchGroup {
  StarlinkLaunchGroup({
    required this.launchKey,
    required List<OmmRecord> members,
  }) : members = List.unmodifiable(members);

  final String launchKey;
  final List<OmmRecord> members;

  int get count => members.length;
  int get minRev =>
      members.map((m) => m.revAtEpoch).reduce((a, b) => a < b ? a : b);
  double get meanMotion =>
      members.map((m) => m.meanMotion).reduce((a, b) => a + b) / count;
  DateTime get latestEpoch =>
      members.map((m) => m.epoch).reduce((a, b) => a.isAfter(b) ? a : b);

  bool get isTrainPhase =>
      minRev <= TrainDetector.maxRevForTrain &&
      meanMotion >= TrainDetector.minMeanMotionForTrain;

  bool get isTight => minRev <= TrainDetector.maxRevForTightTrain;

  String get label => isTight ? 'Starlink train' : 'Starlink string';

  /// Angular spread of the group along its orbit, in degrees of mean anomaly
  /// (circular range).
  double get spreadDeg {
    if (count < 2) return 0;
    final sorted = members.map((m) => m.meanAnomaly % 360).toList()..sort();
    var largestGap = 360 - sorted.last + sorted.first;
    for (var i = 1; i < sorted.length; i++) {
      final gap = sorted[i] - sorted[i - 1];
      if (gap > largestGap) largestGap = gap;
    }
    return (360 - largestGap).clamp(0, 360);
  }

  /// How long the whole train takes to cross a point in the sky.
  Duration get spreadDuration => Duration(
      microseconds: (representative.period.inMicroseconds * spreadDeg / 360)
          .round());

  /// The member we propagate: freshest epoch, ties broken by name.
  OmmRecord get representative {
    final sorted = [...members]..sort((a, b) {
        final c = b.epoch.compareTo(a.epoch);
        return c != 0 ? c : a.objectName.compareTo(b.objectName);
      });
    return sorted.first;
  }
}

class TrainDetector {
  static const maxRevForTrain = 500;
  static const maxRevForTightTrain = 150;
  static const minMeanMotionForTrain = 15.6;

  /// Groups [records] by launch and returns only train-phase groups, newest
  /// first.
  static List<StarlinkLaunchGroup> detect(Iterable<OmmRecord> records) {
    final byLaunch = <String, List<OmmRecord>>{};
    for (final r in records) {
      if (!r.objectName.toUpperCase().startsWith('STARLINK')) continue;
      if (r.launchKey.length < 8) continue;
      byLaunch.putIfAbsent(r.launchKey, () => []).add(r);
    }
    final groups = [
      for (final e in byLaunch.entries)
        if (e.value.length >= 5)
          StarlinkLaunchGroup(launchKey: e.key, members: e.value),
    ].where((g) => g.isTrainPhase).toList()
      ..sort((a, b) => a.minRev.compareTo(b.minRev));
    return groups;
  }
}
