/// Rare comets and novae from the relay's hand-curated list
/// (relay/src/rare_events.ts). The phone never solves an orbit: it
/// interpolates the curated daily RA/Dec rows and turns the nights it can
/// actually be seen from here into [SkyEvent]s.
library;

import '../models/sky_event.dart';
import '../sky/astro.dart';
import '../sky/visibility.dart';

// The defaults, in one place. Comets are LookUp+, a nova is for everyone.
const rareCometPlusOnly = true;
const rareNovaPlusOnly = false;

/// Fainter than this is never listed or pushed, however dark the sky.
const rareMaxMagnitude = 5.0;

/// Clear of the horizon haze, as for pairings.
const _minAltDeg = 10.0;
const _step = Duration(minutes: 10);

enum RareKind { comet, nova }

class RareObject {
  const RareObject({
    required this.id,
    required this.kind,
    required this.name,
    required this.magnitude,
    required this.validUntil,
    required this.note,
    required this.rows,
  });

  final String id;
  final RareKind kind;
  final String name;
  final double magnitude;

  /// The end of its last valid day (UTC).
  final DateTime validUntil;
  final String note;

  /// Daily J2000 places at 0h UT, oldest first.
  final List<({DateTime t, double ra, double dec, double? mag})> rows;

  /// One entry of the relay's list, or null if anything is off: a bad row
  /// means it's dropped, never guessed at.
  static RareObject? fromJson(Object? j) {
    try {
      final m = (j as Map).cast<String, Object?>();
      final kind = RareKind.values.where((k) => k.name == m['kind']).firstOrNull;
      final until = DateTime.parse('${m['validUntil']}T00:00:00Z').add(const Duration(days: 1));
      final rows = [
        for (final r in m['ephemeris'] as List)
          (
            t: DateTime.parse('${(r as Map)['date']}T00:00:00Z'),
            ra: (r['ra'] as num).toDouble(),
            dec: (r['dec'] as num).toDouble(),
            mag: (r['mag'] as num?)?.toDouble(),
          ),
      ];
      final id = m['id'], name = m['name'], note = m['note'];
      if (kind == null || id is! String || name is! String || note is! String || rows.isEmpty) return null;
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i];
        if (r.ra < 0 || r.ra >= 360 || r.dec.abs() > 90) return null;
        if (i > 0 && !r.t.isAfter(rows[i - 1].t)) return null;
      }
      // A comet moves: it needs rows either side of any night it's shown.
      if (kind == RareKind.comet && rows.length < 2) return null;
      return RareObject(
        id: id,
        kind: kind,
        name: name,
        magnitude: (m['magnitude'] as num).toDouble(),
        validUntil: until,
        note: note,
        rows: rows,
      );
    } catch (_) {
      return null;
    }
  }

  /// Where it is (J2000, degrees) and how bright at [utc]; null outside its
  /// rows or after [validUntil]. A nova's single row holds from its date
  /// until then: never before it was found.
  ({double ra, double dec, double mag})? at(DateTime utc) {
    if (!utc.isBefore(validUntil) || utc.isBefore(rows.first.t)) return null;
    if (rows.length == 1) {
      final r = rows.single;
      return (ra: r.ra, dec: r.dec, mag: r.mag ?? magnitude);
    }
    if (utc.isBefore(rows.first.t) || utc.isAfter(rows.last.t)) return null;
    var i = 0;
    while (i < rows.length - 2 && !utc.isBefore(rows[i + 1].t)) {
      i++;
    }
    final a = rows[i], b = rows[i + 1];
    final f = utc.difference(a.t).inSeconds / b.t.difference(a.t).inSeconds;
    final dRa = ((b.ra - a.ra + 540) % 360) - 180;
    final ma = a.mag ?? magnitude, mb = b.mag ?? magnitude;
    return (ra: (a.ra + dRa * f) % 360, dec: a.dec + (b.dec - a.dec) * f, mag: ma + (mb - ma) * f);
  }
}

/// The relay's `{events: [...]}`; entries that don't parse are dropped.
List<RareObject> parseRareEvents(Object? json) {
  final list = json is Map ? json['events'] : null;
  if (list is! List) return const [];
  return [for (final e in list) ?RareObject.fromJson(e)];
}

/// One event a night for each object while it can be seen from here with
/// the naked eye ([canSee] with no weather: sky darkness, twilight and
/// moonlight; the cloud cut-off is the planner's). The event runs from
/// the first moment it's ≥ 10° up and bright enough to the end of that
/// stretch, peaking where it's highest.
List<SkyEvent> rareEventEvents({
  required List<RareObject> objects,
  required DateTime now,
  required double latDeg,
  required double lonDeg,
  required SkyDarkness darkness,
  int days = 7,
}) {
  final out = <SkyEvent>[];
  final u = now.toUtc();
  // On a fixed grid from half a day back, so a night already under way
  // keeps the start (and id) it had when it was first found.
  final grid = _step.inMilliseconds;
  final from = DateTime.fromMillisecondsSinceEpoch(
      (u.subtract(const Duration(hours: 12)).millisecondsSinceEpoch ~/ grid) * grid,
      isUtc: true);
  final to = u.add(Duration(days: days));
  for (final o in objects) {
    final diffuse = o.kind == RareKind.comet;
    final seenNights = <String>{};
    ({DateTime t, Horizontal h, double mag, double ra, double dec})? first, top, last;
    void close() {
      final f = first, p = top, l = last;
      first = top = last = null;
      if (f == null || p == null || l == null || !l.t.isAfter(u)) return;
      final night = _nightKey(f.t, lonDeg);
      if (!seenNights.add(night)) return; // the Moon broke the night in two: keep the first stretch
      final type = o.kind == RareKind.comet ? SkyEventType.comet : SkyEventType.nova;
      out.add(SkyEvent(
        id: '${o.kind.name}:${o.id}:$night',
        type: type,
        start: f.t,
        peak: p.t,
        end: l.t.isAfter(p.t) ? l.t : p.t.add(_step),
        peakElevationDeg: p.h.altitudeDeg,
        riseAzimuthDeg: f.h.azimuthDeg,
        peakAzimuthDeg: p.h.azimuthDeg,
        setAzimuthDeg: l.h.azimuthDeg,
        details: {
          'name': o.name,
          'label': o.name,
          'note': o.note,
          'magnitude': double.parse(p.mag.toStringAsFixed(1)),
          // J2000, for the finder; a comet moves a few degrees a day at most.
          'ra': double.parse(p.ra.toStringAsFixed(3)),
          'dec': double.parse(p.dec.toStringAsFixed(3)),
        },
      ));
    }

    for (var t = from; !t.isAfter(to); t = t.add(_step)) {
      final where = o.at(t);
      if (where == null || where.mag > rareMaxMagnitude) {
        close();
        continue;
      }
      final h = catalogHorizontal(where.ra, where.dec, t, latDeg, lonDeg);
      final ok = h.altitudeDeg >= _minAltDeg &&
          canSee(
            altDeg: h.altitudeDeg,
            mag: where.mag,
            c: SkyConditions.at(t, latDeg, lonDeg),
            darkness: darkness,
            diffuse: diffuse,
          ).worthPlanning;
      if (!ok) {
        close();
        continue;
      }
      final s = (t: t, h: h, mag: where.mag, ra: where.ra, dec: where.dec);
      first ??= s;
      if (top == null || h.altitudeDeg > top!.h.altitudeDeg) top = s;
      last = s;
    }
    close();
  }
  return out..sort((a, b) => a.start.compareTo(b.start));
}

/// The local solar date of the evening a moment belongs to (before local
/// noon counts as the night before), e.g. `20200712`.
String _nightKey(DateTime utc, double lonDeg) {
  final l = utc.add(Duration(minutes: (lonDeg / 15 * 60).round() - 12 * 60));
  return '${l.year}${l.month.toString().padLeft(2, '0')}${l.day.toString().padLeft(2, '0')}';
}
