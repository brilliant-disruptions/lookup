/// The last two minutes before a pass: when the app (if it's open) takes
/// over the screen with a seconds countdown and an arrow to where it'll
/// appear, and the words that arrow speaks. Pure; the screen is
/// `ui/look_up_now_screen.dart`.
library;

import '../models/sky_event.dart';

abstract final class LookUpNow {
  /// How long before it appears the takeover starts.
  static const window = Duration(minutes: 2);

  /// Things that appear at a point on the horizon and cross the sky.
  static const types = {SkyEventType.iss, SkyEventType.tiangong, SkyEventType.starlinkTrain};

  /// Whether [e] is in its final stretch at [now]: a pass, still ahead, at
  /// most [window] away. Never for a past record or the preview pass.
  static bool due(SkyEvent e, DateTime now) {
    if (!types.contains(e.type) || e.details['past'] == true || e.details['demo'] == true) return false;
    final until = e.start.difference(now.toUtc());
    return until > Duration.zero && until <= window;
  }

  /// "1:47", "0:05": minutes and seconds to go, never negative.
  static String clock(Duration d) {
    final s = d.isNegative ? 0 : (d.inMilliseconds / 1000).ceil();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  /// Which way to turn, from the signed difference target − facing in
  /// degrees (positive: the target is clockwise, to the right).
  static String turn(double deltaDeg) {
    final a = deltaDeg.abs();
    if (a <= 15) return 'You\'re facing it';
    if (a >= 150) return 'Turn around';
    final side = deltaDeg > 0 ? 'right' : 'left';
    return a <= 45 ? 'A little to your $side' : 'Turn $side';
  }
}
