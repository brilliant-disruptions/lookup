/// How red night vision makes the screen, like a phone's Auto-Brightness.
///
/// **Auto** follows the light around the phone: outside in the dark the eyes
/// are fully dark-adapted and every bit of non-red light costs that, so it's
/// full deep red; in a lit room adaptation is already gone and red only
/// costs readability, so it's the true colours. In between it fades.
///
/// **How red** is the person's own say. With Auto on, moving it nudges Auto
/// up or down from wherever it is, and Auto carries on following the light
/// from there (a tweak never quietly switches Auto off). With Auto off it's
/// a fixed level all evening. Pure.
library;

import 'dart:math' as math;

/// At or below this the sky is properly dark (civil twilight ends near
/// 3.4 lux; a full Moon gives ~0.3).
const darkLux = 3.0;

/// At or above this it's a lit room (living rooms run ~50–300 lux): Auto
/// gives the true colours.
const brightLux = 150.0;

/// iOS has no light-sensor API, so it stands in screen brightness (0–1),
/// which follows ambient light under Auto-Brightness. Outdoors at night it
/// sits near the bottom; in a lit room around the middle and up.
const darkScreen = 0.15;
const brightScreen = 0.6;

/// Auto's red (0–1) from a light-sensor reading in lux. Log scale, because
/// eyes (and lux) are.
double redStrengthFromLux(double lux) {
  if (lux.isNaN || lux <= darkLux) return 1;
  if (lux >= brightLux) return 0;
  final f = (math.log(lux) - math.log(darkLux)) / (math.log(brightLux) - math.log(darkLux));
  return _between(f);
}

/// Auto's red from screen brightness (0–1), the iOS stand-in.
double redStrengthFromScreen(double brightness) {
  if (brightness.isNaN || brightness <= darkScreen) return 1;
  if (brightness >= brightScreen) return 0;
  return _between((brightness - darkScreen) / (brightScreen - darkScreen));
}

/// f = 0 is dark (full red), 1 is bright (true colours). Snapped to 5 %
/// steps so sensor jitter doesn't repaint the whole screen.
double _between(double f) => ((1 - f) * 20).round() / 20;

/// What the screen shows. [autoRed] is Auto's reading right now (full red
/// when there's no sensor); [nudge] is how far the person moved it from
/// Auto (−1…1); [level] is the fixed red with Auto off.
double nightVisionStrength({required bool auto, required double autoRed, required double nudge, required double level}) =>
    (auto ? autoRed + nudge : level).clamp(0.0, 1.0);

/// The nudge that makes Auto show [target] now, when Auto alone gives
/// [autoRed]. Where Auto goes from there, the nudge goes with it.
double nudgeFor({required double target, required double autoRed}) => (target.clamp(0.0, 1.0) - autoRed).clamp(-1.0, 1.0);
