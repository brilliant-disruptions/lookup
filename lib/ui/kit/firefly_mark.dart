/// The firefly: LookUp's one mark for "it appears here". A warm amber glow
/// round a cream core. The finder flies it; everywhere else it rests.
/// "You're pointing here" is the blue crosshair (`pointing_mark.dart`): on
/// the Sky panorama a resting glow read as the Sun.
///
/// Only `dart:ui`, so the alert art can paint it in the background isolate.
library;

import 'dart:ui';

const fireflyWarm = Color(0xFFFFB347);
const fireflyCore = Color(0xFFFFF3D6);

/// Paints the firefly at [at]. [blink] 0…1 is how bright it is right now
/// (the finder pulses it; at rest it's 0.5). [scale] sizes it for bigger
/// canvases such as the alert picture.
void paintFirefly(Canvas canvas, Offset at, {double blink = 0.5, double scale = 1}) {
  canvas.drawCircle(
      at,
      30 * scale,
      Paint()
        ..color = fireflyWarm.withValues(alpha: 0.18 + 0.32 * blink)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 16 * scale));
  canvas.drawCircle(
      at,
      10 * scale,
      Paint()
        ..color = fireflyWarm.withValues(alpha: 0.5 + 0.4 * blink)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5 * scale));
  canvas.drawCircle(at, 4.5 * scale, Paint()..color = fireflyCore.withValues(alpha: 0.75 + 0.25 * blink));
}
