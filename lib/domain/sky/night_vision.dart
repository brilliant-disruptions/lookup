/// How strongly night vision shifts the screen to red, from the light
/// around the phone. In the dark the eyes are fully dark-adapted and every
/// bit of non-red light costs that, so the shift is full deep red. In a lit
/// room or at dusk adaptation is already gone and readability matters more,
/// so the shift eases off to a light tint. It never switches itself off:
/// the user asked for red.
library;

import 'dart:math' as math;

/// Strength in a bright room or daylight: still visibly red-shifted.
const minRedStrength = 0.3;

/// At or below this the sky is properly dark (civil twilight ends near
/// 3.4 lux; a full Moon gives ~0.3).
const darkLux = 3.0;

/// At or above this it's office-bright indoors or daylight outside.
const brightLux = 400.0;

/// iOS has no light-sensor API, so it stands in screen brightness (0–1),
/// which follows ambient light under Auto-Brightness. Outdoors at night it
/// sits near the bottom; in a lit room around the middle.
const darkScreen = 0.15;
const brightScreen = 0.7;

/// Strength from a light-sensor reading in lux. Log scale, because eyes
/// (and lux) are.
double redStrengthFromLux(double lux) {
  if (lux.isNaN || lux <= darkLux) return 1;
  if (lux >= brightLux) return minRedStrength;
  final f = (math.log(lux) - math.log(darkLux)) / (math.log(brightLux) - math.log(darkLux));
  return _between(f);
}

/// Strength from screen brightness (0–1), the iOS stand-in.
double redStrengthFromScreen(double brightness) {
  if (brightness.isNaN || brightness <= darkScreen) return 1;
  if (brightness >= brightScreen) return minRedStrength;
  return _between((brightness - darkScreen) / (brightScreen - darkScreen));
}

/// f = 0 is dark (full red), 1 is bright. Snapped to 5 % steps so sensor
/// jitter doesn't repaint the whole screen.
double _between(double f) {
  final s = 1 - f * (1 - minRedStrength);
  return (s * 20).round() / 20;
}
