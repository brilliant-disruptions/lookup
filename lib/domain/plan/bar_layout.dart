/// Where each sight's marker goes on a night bar (pure maths, no Flutter).
///
/// A marker's icon is centred on its real time, so the marker never moves
/// sideways to make room: when two would overlap, the later one drops to
/// another row at the same time. If the name doesn't fit it shrinks to just
/// its icon. Nothing is displaced from its time, so nothing needs a leader
/// line, and nothing is ever drawn across another sight.
library;

import 'dart:math' as math;

/// One marker's place: `left` and `width` in pixels, `lane` 0 at the top.
class BarSlot {
  const BarSlot({required this.left, required this.width, required this.lane, required this.named, required this.tick});
  final double left, width, tick;
  final int lane;

  /// True when the name sits beside the icon; false for the icon alone.
  final bool named;

  @override
  String toString() => 'BarSlot(left: $left, width: $width, lane: $lane, named: $named)';
}

/// Rows past this many are only used when the icon alone won't fit either.
const barPreferredLanes = 2;
const barMaxLanes = 4;

/// `timeX[i]` is event i's time in pixels along the bar (events in time
/// order); `namedWidth[i]` the width of its marker with the name.
List<BarSlot> layoutBar({
  required List<double> timeX,
  required List<double> namedWidth,
  required double width,
  double icon = 26,
  double gap = 3,
  double edge = 2,
}) {
  assert(timeX.length == namedWidth.length);
  final ends = <double>[]; // right edge of the last marker in each lane
  final out = <BarSlot>[];

  bool fits(int lane, double left, double w) {
    if (left < edge || left + w > width - edge) return false;
    return lane >= ends.length || left >= ends[lane] + gap;
  }

  BarSlot put(int lane, double left, double w, bool named, double tick) {
    while (ends.length <= lane) {
      ends.add(double.negativeInfinity);
    }
    ends[lane] = left + w;
    return BarSlot(left: left, width: w, lane: lane, named: named, tick: tick);
  }

  for (var i = 0; i < timeX.length; i++) {
    final tick = timeX[i].clamp(edge + icon / 2, width - edge - icon / 2).toDouble();
    final left = tick - icon / 2;
    final nw = namedWidth[i];
    BarSlot? slot;
    // Named in the first rows, then the icon alone in them, then more rows.
    final tries = <(int, bool)>[
      for (var l = 0; l < barPreferredLanes; l++) (l, true),
      for (var l = 0; l < barPreferredLanes; l++) (l, false),
      for (var l = barPreferredLanes; l < barMaxLanes; l++) ...[(l, true), (l, false)],
    ];
    for (final (lane, named) in tries) {
      final w = named ? nw : icon;
      if (fits(lane, left, w)) {
        slot = put(lane, left, w, named, tick);
        break;
      }
    }
    // Only when several land within minutes of each other: share the row
    // that frees up first rather than draw a fifth.
    slot ??= () {
      while (ends.length < barMaxLanes) {
        ends.add(double.negativeInfinity);
      }
      var lane = 0;
      for (var l = 1; l < barMaxLanes; l++) {
        if (ends[l] < ends[lane]) lane = l;
      }
      final l = math.max(left, ends[lane] + gap);
      return put(lane, math.min(l, width - edge - icon), icon, false, tick);
    }();
    out.add(slot);
  }
  return out;
}
