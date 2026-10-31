/// Whether the screen should be red right now. Night vision is either on
/// (the switch), or comes on by itself on the screens used outside once
/// it's dark there, unless the person has said otherwise on that screen.
/// Pure.
library;

/// Sun this far below the horizon counts as dark: civil twilight's end,
/// when the first stars and the station show and eyes start adapting.
const nightSafeSunDeg = -6.0;

bool nightVisionNow({required bool manual, required bool auto, required bool outside, required double? sunAltitudeDeg, bool? override}) {
  if (override != null && outside) return override;
  if (manual) return true;
  return auto && outside && sunAltitudeDeg != null && sunAltitudeDeg <= nightSafeSunDeg;
}
