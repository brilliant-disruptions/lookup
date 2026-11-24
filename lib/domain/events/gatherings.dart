/// Memorable moments: three or more bright things (the Moon, the planets and
/// the first-magnitude stars on the Sun's path) gathered close enough to
/// catch in one look, such as Mars, Jupiter and Regulus in late November 2026.
///
/// Everything here is computed on the phone from the same planet and Moon
/// maths as pairings and occultations. No feed is asked, so no gathering ever
/// waits on a download or costs a request.
library;

import 'dart:math' as math;

import '../models/sky_event.dart';
import '../sky/astro.dart';
import '../sky/sun.dart';

/// Everything in the group fits inside this (the widest pair), about what
/// binoculars show and well inside a fist held at arm's length.
const gatheringFitDeg = 5.0;

/// Clear of the horizon haze, as for pairings.
const gatheringMinAltDeg = 10.0;

/// How far back the search starts, so a gathering that began before today
/// keeps the same id (and so the same alert) as the nights go by.
const gatheringLookBack = Duration(days: 21);

/// The bright stars the Moon and planets pass (J2000, from `stars.json`).
const gatheringStars = <(String, double, double)>[
  ('Regulus', 152.093, 11.967),
  ('Spica', 201.298, -11.161),
  ('Antares', 247.352, -26.432),
  ('Aldebaran', 68.98, 16.509),
  ('Pollux', 116.329, 28.026),
];

class _Body {
  const _Body(this.label, this.moves, this.eq, this.horizontal);
  final String label;

  /// The Moon or a planet. A gathering needs two of these: stars never
  /// gather on their own.
  final bool moves;
  final Equatorial Function(DateTime) eq;
  final Horizontal Function(DateTime, double, double) horizontal;
}

List<_Body> _bodies() => [
      _Body('Moon', true, moonEquatorial, moonHorizontal),
      for (final p in Planet.values)
        _Body(p.label, true, (t) => planetEquatorial(p, t), (t, la, lo) => planetHorizontal(p, t, la, lo)),
      for (final (name, ra, dec) in gatheringStars)
        _Body(name, false, (t) => catalogEquatorial(ra, dec, t), (t, la, lo) => catalogHorizontal(ra, dec, t, la, lo)),
    ];

/// The groups of three or more of [pos] that all fit in [fit] degrees and
/// hold at least two movers. Maximal only: when the Moon joins a trio, the
/// four are the group, not the trio as well.
List<List<int>> _groups(List<_Body> bodies, List<Equatorial?> pos, double fit) {
  final n = bodies.length;
  final near = List.generate(n, (_) => <int>{});
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      final a = pos[i], b = pos[j];
      if (a == null || b == null) continue;
      if (equatorialSeparationDeg(a, b) <= fit) {
        near[i].add(j);
        near[j].add(i);
      }
    }
  }
  final out = <List<int>>[];
  // Bron–Kerbosch: a dozen bodies, so this is instant.
  void grow(Set<int> r, Set<int> p, Set<int> x) {
    if (p.isEmpty && x.isEmpty) {
      if (r.length >= 3 && r.where((i) => bodies[i].moves).length >= 2) out.add(r.toList()..sort());
      return;
    }
    for (final v in p.toList()) {
      grow({...r, v}, p.intersection(near[v]), x.intersection(near[v]));
      p.remove(v);
      x.add(v);
    }
  }

  grow({}, {for (var i = 0; i < n; i++) i}, {});
  return out;
}

double _spread(List<Equatorial> eqs) {
  var w = 0.0;
  for (var i = 0; i < eqs.length; i++) {
    for (var j = i + 1; j < eqs.length; j++) {
      final s = equatorialSeparationDeg(eqs[i], eqs[j]);
      if (s > w) w = s;
    }
  }
  return w;
}

/// One night's best look at a group: when its lowest member is highest, in
/// a dark sky (Sun 6° down), with everything at least 10° up.
class _Night {
  _Night(this.at, this.spread, this.lowest, this.alt, this.az, this.nightStart);
  final DateTime at;
  final double spread;
  final double lowest;
  final double alt;
  final double az;
  final DateTime nightStart;
}

/// Memorable moments over the next [days] at this place: one event per
/// gathering, on its tightest night still to come, saying how many nights
/// it can be seen. Its id is the group and the first night it showed, so it
/// stays the same from one refresh to the next.
List<SkyEvent> gatheringEvents({
  required DateTime now,
  required double latDeg,
  required double lonDeg,
  int days = 14,
  double fitDeg = gatheringFitDeg,
}) {
  final bodies = _bodies();
  final u = now.toUtc();
  final limit = u.add(Duration(days: days));
  // key → the nights it was seen, in order.
  final runs = <String, List<List<_Night>>>{};
  final members = <String, List<int>>{};

  var cursor = u.subtract(gatheringLookBack);
  while (cursor.isBefore(limit)) {
    final w = nextDarkWindow(cursor, latDeg, lonDeg, within: const Duration(hours: 30), step: const Duration(minutes: 10));
    if (w == null) break;
    cursor = w.end.add(const Duration(hours: 1));
    // First a cheap screen in the middle of the night, from anywhere on Earth
    // (a little wider: the group drifts over a night).
    final mid = w.start.add(w.end.difference(w.start) ~/ 2);
    final midEq = [for (final b in bodies) b.eq(mid)];
    final candidates = _groups(bodies, midEq, fitDeg + 1);
    if (candidates.isEmpty) continue;
    // Then through the night from here, every 20 minutes.
    final best = <String, _Night>{};
    for (var t = w.start; !t.isAfter(w.end); t = t.add(const Duration(minutes: 20))) {
      final eq = <Equatorial?>[for (var i = 0; i < bodies.length; i++) null];
      final hz = <int, Horizontal>{};
      for (final g in candidates) {
        for (final i in g) {
          if (hz.containsKey(i)) continue;
          final h = bodies[i].horizontal(t, latDeg, lonDeg);
          hz[i] = h;
          if (h.altitudeDeg >= gatheringMinAltDeg) eq[i] = bodies[i].eq(t);
        }
      }
      for (final g in _groups(bodies, eq, fitDeg)) {
        final key = [for (final i in g) bodies[i].label].join('+');
        final lowest = g.map((i) => hz[i]!.altitudeDeg).reduce((a, b) => a < b ? a : b);
        final have = best[key];
        if (have != null && have.lowest >= lowest) continue;
        final alt = g.map((i) => hz[i]!.altitudeDeg).reduce((a, b) => a + b) / g.length;
        best[key] = _Night(t, _spread([for (final i in g) eq[i]!]), lowest, alt, _meanAz([for (final i in g) hz[i]!.azimuthDeg]), w.start);
        members[key] = g;
      }
    }
    for (final MapEntry(:key, :value) in best.entries) {
      final list = runs.putIfAbsent(key, () => []);
      // A night or two missed (a bright Moon set early, a low pass) doesn't
      // end the run; three does.
      if (list.isNotEmpty && value.nightStart.difference(list.last.last.nightStart) <= const Duration(days: 3)) {
        list.last.add(value);
      } else {
        list.add([value]);
      }
    }
  }

  final out = <SkyEvent>[];
  for (final MapEntry(:key, value: list) in runs.entries) {
    for (final run in list) {
      // The tightest night not gone yet; earlier nights still count.
      final ahead = run.where((n) => n.at.add(const Duration(hours: 1)).isAfter(u) && n.at.isBefore(limit)).toList();
      if (ahead.isEmpty) continue;
      final pick = ahead.reduce((a, b) => b.spread < a.spread ? b : a);
      final labels = key.split('+');
      final first = run.first.nightStart.toUtc();
      out.add(SkyEvent(
        id: 'gather:$key:${first.year}-${first.month}-${first.day}',
        type: SkyEventType.gathering,
        start: pick.at,
        peak: pick.at,
        end: pick.at.add(const Duration(minutes: 60)),
        peakElevationDeg: pick.alt,
        riseAzimuthDeg: pick.az,
        peakAzimuthDeg: pick.az,
        setAzimuthDeg: pick.az,
        details: {
          'bodies': labels,
          'label': _join(labels),
          'separation': double.parse(pick.spread.toStringAsFixed(1)),
          'nights': run.length,
          'nightsLeft': ahead.length,
          'from': run.first.at.toIso8601String(),
          'to': run.last.at.toIso8601String(),
          'when': _when(pick.at, lonDeg),
        },
      ));
    }
  }
  // Two groups sharing bodies on the same night (the Moon with Mars and
  // Regulus, and with Jupiter and Regulus) are one look: keep the tighter.
  double sep(SkyEvent e) => (e.details['separation'] as num).toDouble();
  bool overlaps(SkyEvent a, SkyEvent b) =>
      a.start.difference(b.start).abs() < const Duration(hours: 12) &&
      (a.details['bodies'] as List).where((x) => (b.details['bodies'] as List).contains(x)).length >= 2;
  final kept = out.where((e) => !out.any((o) => o != e && overlaps(e, o) && (sep(o) < sep(e) || (sep(o) == sep(e) && o.id.compareTo(e.id) < 0)))).toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  return kept;
}

/// "Mars, Jupiter and Regulus".
String _join(List<String> l) => l.length < 2 ? l.join() : '${l.sublist(0, l.length - 1).join(', ')} and ${l.last}';

/// Evening or morning, by the local solar hour.
String _when(DateTime utc, double lonDeg) {
  final h = (utc.hour + utc.minute / 60 + lonDeg / 15) % 24;
  return h >= 12 ? 'evening' : 'morning';
}

double _meanAz(List<double> az) {
  var x = 0.0, y = 0.0;
  for (final a in az) {
    x += math.cos(a * math.pi / 180);
    y += math.sin(a * math.pi / 180);
  }
  final m = math.atan2(y, x) * 180 / math.pi;
  return m < 0 ? m + 360 : m;
}

/// How close they are, in words someone can hold up to the sky (never
/// degrees): "Close enough to hide behind your thumb", "All in one
/// binocular view".
String gatheringFitWords(SkyEvent e) {
  final sep = (e.details['separation'] as num?)?.toDouble() ?? gatheringFitDeg;
  final n = (e.details['bodies'] as List?)?.length ?? 3;
  final who = n == 3 ? 'All three' : 'All $n';
  if (sep <= 2) return '$who close enough to hide behind your thumb';
  if (sep <= 3.5) return '$who in a two-finger width at arm\'s length';
  return '$who in one binocular view';
}

/// "Tightest tonight; there for 9 nights." when it spans several nights,
/// so a cloudy evening isn't the only chance. Empty for one night.
String gatheringNightsWords(SkyEvent e) {
  final left = (e.details['nightsLeft'] as num?)?.toInt() ?? 1;
  if (left <= 1) return 'One night only.';
  return 'Closest this night, and there for $left nights in all.';
}

/// Pairings with the gatherings they're part of taken out, so LookUp+
/// doesn't tap twice for the same patch of sky ("Mars and Jupiter" and then
/// "Mars, Jupiter and Regulus"). On free the pairing stays: it's their tap.
Iterable<SkyEvent> withoutGathered(Iterable<SkyEvent> pairings, List<SkyEvent> gatherings, {required bool isPlus}) {
  if (!isPlus || gatherings.isEmpty) return pairings;
  bool inside(SkyEvent p, SkyEvent g) {
    final pb = (p.details['bodies'] as List?) ?? const [];
    final gb = (g.details['bodies'] as List?) ?? const [];
    if (!pb.every(gb.contains)) return false;
    final from = DateTime.tryParse('${g.details['from']}'), to = DateTime.tryParse('${g.details['to']}');
    if (from == null || to == null) return false;
    return !p.start.isBefore(from.subtract(const Duration(hours: 18))) && !p.start.isAfter(to.add(const Duration(hours: 18)));
  }

  return pairings.where((p) => !gatherings.any((g) => inside(p, g)));
}

/// The memorable moment Home calls out as "Don't miss" for LookUp+: the
/// next gathering in the coming [within], or null. Free never gets one
/// (it isn't their tap; asks go through the soft-ask budget instead).
SkyEvent? dontMiss(Iterable<SkyEvent> events, DateTime now, {required bool isPlus, Duration within = const Duration(days: 7)}) {
  if (!isPlus) return null;
  final u = now.toUtc();
  return events
      .where((e) => e.type == SkyEventType.gathering && e.end.isAfter(u) && e.start.isBefore(u.add(within)))
      .firstOrNull;
}
