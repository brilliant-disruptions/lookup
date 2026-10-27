/// Things that move across the sky in minutes (the stations, Starlink
/// trains) drawn as their track: where they come up, which way they go,
/// where they set, and where they are now while it's happening.
library;

import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../../domain/models/sky_event.dart';
import '../../domain/sky/astro.dart';
import '../finder_screen.dart';
import '../format.dart';
import '../kit/event_style.dart';

class SkyTrack {
  SkyTrack(this.event, this.points) : color = eventStyle(event.type, details: event.details).color;

  final SkyEvent event;

  /// Sampled along the pass, rise to set.
  final List<({DateTime t, Horizontal h})> points;
  final Color color;

  bool liveAt(DateTime now) => !now.toUtc().isBefore(event.start) && now.toUtc().isBefore(event.end);

  /// "ISS flyover 4:42 AM".
  String get label => '${eventTitle(event)} ${fmtTime(event.start)}';

  /// Where it is at [now], between samples; null outside the pass.
  Horizontal? at(DateTime now) {
    final u = now.toUtc();
    if (!liveAt(u) || points.length < 2) return null;
    for (var i = 1; i < points.length; i++) {
      final b = points[i];
      if (b.t.isBefore(u)) continue;
      final a = points[i - 1];
      final span = b.t.difference(a.t).inMilliseconds;
      final f = span <= 0 ? 0.0 : u.difference(a.t).inMilliseconds / span;
      final daz = ((b.h.azimuthDeg - a.h.azimuthDeg + 540) % 360) - 180;
      return Horizontal((a.h.azimuthDeg + daz * f) % 360, a.h.altitudeDeg + (b.h.altitudeDeg - a.h.altitudeDeg) * f);
    }
    return points.last.h;
  }
}

/// Passes that move across the sky, from the orbit when the event carries
/// one (as the finder does), otherwise a smooth arc through rise, peak and
/// set.
const trackedTypes = {SkyEventType.iss, SkyEventType.tiangong, SkyEventType.starlinkTrain, SkyEventType.satellitePass};

SkyTrack passTrack(SkyEvent e, double lat, double lon) {
  final live = FinderTarget(e, latDeg: lat, lonDeg: lon).path;
  if (live.length >= 2) {
    return SkyTrack(e, [for (final p in live) (t: p.t, h: Horizontal(p.d.azimuthDeg, p.d.elevationDeg))]);
  }
  return SkyTrack(e, _arc(e));
}

/// The next few passes worth drawing from [now]: any happening, then the
/// coming [within] hours, at most [max].
Iterable<SkyEvent> upcomingPasses(Iterable<SkyEvent> events, DateTime now,
    {Duration within = const Duration(hours: 12), int max = 3}) {
  final u = now.toUtc();
  return events
      .where((e) => trackedTypes.contains(e.type) && e.end.isAfter(u) && e.start.isBefore(u.add(within)))
      .take(max);
}

List<({DateTime t, Horizontal h})> _arc(SkyEvent e) {
  const n = 32;
  final total = e.end.difference(e.start).inMilliseconds;
  final pf = total <= 0 ? 0.5 : (e.peak.difference(e.start).inMilliseconds / total).clamp(0.1, 0.9);
  double turn(double from, double to) => ((to - from + 540) % 360) - 180;
  return [
    for (var i = 0; i <= n; i++)
      () {
        final f = i / n;
        final first = f <= pf;
        final local = first ? f / pf : (f - pf) / (1 - pf);
        final az = first
            ? e.riseAzimuthDeg + turn(e.riseAzimuthDeg, e.peakAzimuthDeg) * local
            : e.peakAzimuthDeg + turn(e.peakAzimuthDeg, e.setAzimuthDeg) * local;
        final up = first ? local : 1 - local;
        return (
          t: e.start.add(Duration(milliseconds: (total * f).round())),
          h: Horizontal(az % 360, e.peakElevationDeg * (1 - (1 - up) * (1 - up))),
        );
      }(),
  ];
}

/// Draws [tr] from its points already projected to the screen (null where
/// out of view): solid where it has already been, dashed ahead, arrows for
/// which way it goes, its name at the start and a dot where it is now.
/// [maxJump] breaks the line where a projection wraps round an edge; the
/// name is kept inside [bounds].
void paintTrack(Canvas canvas, SkyTrack tr, List<Offset?> pts, DateTime now, TextStyle label,
    {required double maxJump, required Rect bounds, Offset? liveAt}) {
  final u = now.toUtc();
  final solid = Paint()
    ..color = tr.color
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round;
  final dash = Paint()
    ..color = tr.color.withValues(alpha: 0.85)
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round;
  var phase = 0.0, sinceArrow = 40.0;
  Offset? first;
  for (var i = 1; i < pts.length; i++) {
    final a = pts[i - 1], b = pts[i];
    if (a == null || b == null || (b - a).distance > maxJump) continue;
    first ??= a;
    final flown = !tr.points[i].t.isAfter(u);
    if (flown) {
      canvas.drawLine(a, b, solid);
      continue;
    }
    // Dashes, 7 on and 5 off, carried across segments.
    final len = (b - a).distance;
    final dir = (b - a) / (len == 0 ? 1 : len);
    var d = 0.0;
    while (d < len) {
      final on = phase < 7;
      // At least half a pixel per step, so rounding can never stall the loop.
      final step = math.max(on ? 7 - phase : 12 - phase, 0.5);
      final e = math.min(d + step, len);
      if (on) canvas.drawLine(a + dir * d, a + dir * e, dash);
      phase = (phase + (e - d)) % 12;
      d = e;
    }
    // An arrowhead every ~90 px, pointing the way it travels.
    sinceArrow += len;
    if (sinceArrow > 90 && len > 0) {
      sinceArrow = 0;
      final m = (a + b) / 2;
      final n = Offset(-dir.dy, dir.dx);
      canvas.drawPath(
          Path()
            ..moveTo(m.dx + dir.dx * 6, m.dy + dir.dy * 6)
            ..lineTo(m.dx - dir.dx * 4 + n.dx * 5, m.dy - dir.dy * 4 + n.dy * 5)
            ..lineTo(m.dx - dir.dx * 4 - n.dx * 5, m.dy - dir.dy * 4 - n.dy * 5)
            ..close(),
          Paint()..color = tr.color);
    }
  }
  if (first == null) return;

  // Where it comes into view, and what it is.
  canvas.drawCircle(first, 4, Paint()..color = tr.color);
  final tp = TextPainter(
    text: TextSpan(text: tr.label, style: label.copyWith(fontSize: 11, fontWeight: FontWeight.w700, color: tr.color)),
    textDirection: TextDirection.ltr,
  )..layout();
  final w = tp.width + 14, h = tp.height + 6;
  final box = Rect.fromLTWH(
    (first.dx - w / 2).clamp(bounds.left + 4, math.max(bounds.left + 4, bounds.right - w - 4)),
    (first.dy - h - 10).clamp(bounds.top + 4, math.max(bounds.top + 4, bounds.bottom - h - 4)),
    w,
    h,
  );
  canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(8)), Paint()..color = const Color(0xD904060B));
  tp.paint(canvas, box.topLeft + const Offset(7, 3));

  if (liveAt != null) {
    canvas.drawCircle(
        liveAt,
        14,
        Paint()
          ..color = tr.color.withValues(alpha: 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    canvas.drawCircle(liveAt, 5.5, Paint()..color = const Color(0xFFFFFFFF));
  }
}

/// Whether [p] is within reach of a finger of the projected track.
bool nearTrack(List<Offset?> pts, Offset p, {double reach = 22}) =>
    pts.any((o) => o != null && (o - p).distance < reach);
