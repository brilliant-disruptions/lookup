/// What LookUp has scheduled, and what has already gone out. Pure.
///
/// A refresh replaces the schedule: alerts no longer planned are cancelled.
/// It must only ever cancel what's still *waiting*. Cancelling one that has
/// been delivered takes it off the Lock Screen, and forgetting it lets it
/// be sent again (an "aurora now" chiming at every refresh) or lets the
/// night's cap be filled twice. So each alert is kept here with when it
/// fires, and once that time has passed it's history, not schedule.
library;

class AlertRecord {
  const AlertRecord({required this.id, required this.eventId, required this.fireAt, required this.peak, this.counts = true});

  /// The notification's id.
  final int id;
  final String eventId;

  /// When it goes (or went) out, UTC.
  final DateTime fireAt;

  /// The event's peak: which night it belongs to.
  final DateTime peak;

  /// Whether it uses one of the night's taps (the cap). "Aurora now"
  /// doesn't: it's outside the cap.
  final bool counts;

  Map<String, Object?> toJson() => {
        'id': id,
        'e': eventId,
        'at': fireAt.toUtc().millisecondsSinceEpoch,
        'peak': peak.toUtc().millisecondsSinceEpoch,
        if (!counts) 'free': true,
      };

  static AlertRecord? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], e = j['e'], at = j['at'], peak = j['peak'];
    if (id is! int || e is! String || at is! int || peak is! int) return null;
    return AlertRecord(
      id: id,
      eventId: e,
      fireAt: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
      peak: DateTime.fromMillisecondsSinceEpoch(peak, isUtc: true),
      counts: j['free'] != true,
    );
  }
}

abstract final class AlertLedger {
  /// How long a delivered alert is remembered: through its night (for the
  /// cap) and its event (an aurora's three hours).
  static const keep = Duration(hours: 36);

  /// [records] split at [now]: those that have gone out (and are still
  /// worth remembering), and the ids of those still waiting.
  static ({List<AlertRecord> delivered, Set<int> pending}) at(Iterable<AlertRecord> records, DateTime now) {
    final u = now.toUtc();
    final delivered = <AlertRecord>[];
    final pending = <int>{};
    for (final r in records) {
      if (r.fireAt.isAfter(u)) {
        pending.add(r.id);
      } else if (u.difference(r.fireAt) <= keep) {
        delivered.add(r);
      }
    }
    return (delivered: delivered, pending: pending);
  }

  /// The events already tapped for, with their peaks: what the planner
  /// counts against each night's cap.
  static Map<String, DateTime> alerted(Iterable<AlertRecord> delivered) =>
      {for (final r in delivered) if (r.counts) r.eventId: r.peak};

  /// What to remember after a refresh: what went out before, and the new schedule.
  static List<AlertRecord> next(Iterable<AlertRecord> delivered, Iterable<AlertRecord> planned) {
    final ids = {for (final p in planned) p.id};
    return [...delivered.where((d) => !ids.contains(d.id)), ...planned];
  }
}
