/// Whether the screen should be red right now: night vision is on (it is
/// unless they switch it off in Settings) and the Sun is down where they
/// are, sunset to sunrise. How deep the red goes is the light around the
/// phone's call (night_vision.dart). Pure.
library;

/// The Sun's centre this far down is sunset and sunrise: its top edge on
/// the horizon, refraction included (the almanac's −50′).
const sunsetSunDeg = -0.833;

bool nightVisionNow({required bool enabled, required double? sunAltitudeDeg}) =>
    enabled && sunAltitudeDeg != null && sunAltitudeDeg < sunsetSunDeg;
