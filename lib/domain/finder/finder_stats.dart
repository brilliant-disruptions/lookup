/// How well Pip gets people onto the target, kept on the phone only: the
/// share of finder sessions that lock on, and the median time to the first
/// lock. Nothing leaves the device.
library;

class FinderStats {
  const FinderStats({this.sessions = 0, this.locks = 0, this.lockSeconds = const []});

  /// Finder sessions that had a compass reading (no sensor, no chance).
  final int sessions;

  /// Of those, the ones that reached the target at least once.
  final int locks;

  /// Seconds to the first lock, the latest [keep] only.
  final List<double> lockSeconds;

  static const keep = 50;

  /// Locks per session, or null before the first session.
  double? get lockRate => sessions == 0 ? null : locks / sessions;

  /// Median seconds to lock over the latest [keep], or null with none.
  double? get medianLockSeconds {
    if (lockSeconds.isEmpty) return null;
    final s = [...lockSeconds]..sort();
    final m = s.length ~/ 2;
    return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
  }

  /// One more session; [toLock] is how long the first lock took, null if none.
  FinderStats record(Duration? toLock) => FinderStats(
    sessions: sessions + 1,
    locks: locks + (toLock == null ? 0 : 1),
    lockSeconds: toLock == null
        ? lockSeconds
        : [...lockSeconds, toLock.inMilliseconds / 1000].skip((lockSeconds.length + 1 - keep).clamp(0, keep)).toList(),
  );

  Map<String, dynamic> toJson() => {'sessions': sessions, 'locks': locks, 'lockSeconds': lockSeconds};

  factory FinderStats.fromJson(Map<String, dynamic> j) => FinderStats(
    sessions: j['sessions'] as int? ?? 0,
    locks: j['locks'] as int? ?? 0,
    lockSeconds: [for (final x in (j['lockSeconds'] as List? ?? const [])) (x as num).toDouble()],
  );
}
