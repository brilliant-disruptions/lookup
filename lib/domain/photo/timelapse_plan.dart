/// Timelapses: set the phone up where LookUp says, and it starts by itself
/// when the thing appears (it rises clear of the trees, or the event
/// begins) and stops when it's gone, or when you stop it. This is the
/// plan: the window, how often to keep a frame, where to point, and how
/// long the clip comes out. Pure Dart.
library;

import 'dart:math' as math;

import 'camera.dart';
import 'framing.dart';

/// High enough to be clear of trees and rooftops.
const timelapseMinAltitudeDeg = 8.0;

/// What a clip aims to run to, at [timelapseFps].
const timelapseTargetClipS = 15.0;
const timelapseFps = 30;

/// When to record, from [now]. An event (a pass, a shower's peak) runs from
/// a little before its [eventStart] to a little after its [eventEnd].
/// Anything else is recorded from when [altitudeAt] first puts it
/// [minAltDeg] up (or now, if it already is) until it sinks below that,
/// the night ends ([nightEnd]), or [maxLength] has run. Null when it's over,
/// or won't be up in the next day.
({DateTime start, DateTime end})? timelapseWindow({
  required DateTime now,
  DateTime? eventStart,
  DateTime? eventEnd,
  double Function(DateTime utc)? altitudeAt,
  DateTime? nightEnd,
  double minAltDeg = timelapseMinAltitudeDeg,
  Duration maxLength = const Duration(hours: 6),
  Duration step = const Duration(minutes: 2),
}) {
  final t0 = now.toUtc();
  if (eventStart != null && eventEnd != null) {
    final end = eventEnd.add(const Duration(seconds: 30));
    if (!end.isAfter(t0)) return null;
    final start = eventStart.subtract(const Duration(seconds: 30));
    return (start: start.isBefore(t0) ? t0 : start, end: end);
  }
  if (altitudeAt == null) return null;
  DateTime? start;
  for (var t = t0; t.isBefore(t0.add(const Duration(days: 1))); t = t.add(step)) {
    if (altitudeAt(t) >= minAltDeg) {
      start = t;
      break;
    }
  }
  if (start == null) return null;
  var limit = start.add(maxLength);
  if (nightEnd != null && nightEnd.isAfter(start) && nightEnd.isBefore(limit)) limit = nightEnd;
  var end = limit;
  for (var t = start.add(step); t.isBefore(limit); t = t.add(step)) {
    if (altitudeAt(t) < minAltDeg) {
      end = t;
      break;
    }
  }
  return (start: start, end: end);
}

class TimelapsePlan {
  const TimelapsePlan({
    required this.start,
    required this.end,
    required this.interval,
    required this.framing,
    this.fps = timelapseFps,
  });

  final DateTime start, end;

  /// One frame kept every [interval].
  final Duration interval;

  /// Where to point and which lens; null when there's no path to frame.
  final Framing? framing;
  final int fps;

  Duration get length => end.difference(start);

  /// Frames the whole window makes.
  int get frames => length.inMilliseconds ~/ interval.inMilliseconds + 1;

  /// How long the clip plays.
  double get clipSeconds => frames / fps;

  /// How many times faster than life it plays.
  double get speedUp => interval.inMilliseconds / 1000 * fps;
}

/// Plans a timelapse over [start]–[end] with frames [shutterS] long, the
/// thing's [path] over the window, and the phone's [lenses]: one frame
/// every so often so the clip runs about [targetClipS], never faster than
/// the camera can take them, never sparser than one a minute.
TimelapsePlan planTimelapse({
  required DateTime start,
  required DateTime end,
  required double shutterS,
  List<PathPoint> path = const [],
  List<CameraLens> lenses = const [],
  int fps = timelapseFps,
  double targetClipS = timelapseTargetClipS,
}) {
  final windowS = math.max(1, end.difference(start).inMilliseconds) / 1000;
  var s = windowS / (targetClipS * fps);
  s = s.clamp(math.max(1.0, shutterS + 0.5), 60.0);
  if (s >= 2) s = s.roundToDouble();
  return TimelapsePlan(
    start: start,
    end: end,
    interval: Duration(milliseconds: (s * 1000).round()),
    framing: path.isEmpty || lenses.isEmpty ? null : frameFor(path, lenses),
    fps: fps,
  );
}

enum TimelapseStage {
  /// Set up and waiting for it to appear.
  waiting,
  recording,

  /// It's gone, or you stopped it.
  done,
}

/// Where the timelapse is at [now]. [startedEarly] is when you started it
/// by hand before it appeared; [stoppedAt] when you stopped it.
TimelapseStage timelapseStage(DateTime now, TimelapsePlan p, {DateTime? startedEarly, DateTime? stoppedAt}) {
  final t = now.toUtc();
  if (stoppedAt != null && !t.isBefore(stoppedAt)) return TimelapseStage.done;
  if (!t.isBefore(p.end)) return TimelapseStage.done;
  if (t.isBefore(p.start) && (startedEarly == null || t.isBefore(startedEarly))) return TimelapseStage.waiting;
  return TimelapseStage.recording;
}

/// Whether to keep the frame arriving at [now]: the first one, then one
/// every [interval] (a frame a little early still counts, so a camera
/// that's a few milliseconds quick doesn't skip every other one).
bool keepTimelapseFrame(DateTime now, DateTime? lastKept, Duration interval) =>
    lastKept == null || now.difference(lastKept) >= interval - const Duration(milliseconds: 150);
