/// Where the phone points: an open crosshair in the app's blue. Lines only,
/// no dot and no glow, so it can't be read as the Sun, a planet or a star;
/// the gap in the middle leaves the star you're aiming at showing through.
/// The firefly keeps its one job, "it appears here".
library;

import 'dart:ui';

const pointingBlue = Color(0xFF5AA2FF);

/// Paints the crosshair centred on [at].
void paintPointingMark(Canvas canvas, Offset at) {
  const gap = 6.0, arm = 11.0;
  // A thin dark edge under each stroke keeps it clear over the Milky Way.
  final edge = Paint()
    ..color = const Color(0xB304060B)
    ..strokeWidth = 4
    ..strokeCap = StrokeCap.round;
  final line = Paint()
    ..color = pointingBlue
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round;
  for (final paint in [edge, line]) {
    for (final d in const [Offset(1, 0), Offset(-1, 0), Offset(0, 1), Offset(0, -1)]) {
      canvas.drawLine(at + d * gap, at + d * (gap + arm), paint);
    }
  }
}
