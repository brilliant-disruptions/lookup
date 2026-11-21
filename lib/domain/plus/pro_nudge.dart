/// When LookUp may mention the Pro camera, and what it says.
///
/// Free users take pictures with Pip and that's never in the way: no choice
/// sheet, no tag on "Photograph it". The Pro camera is mentioned in one
/// place, the moment after a catch, as a single line they can wave away:
///
/// - never on someone's first catch (that one is theirs to enjoy);
/// - only for what the Pro camera really does better (the Moon, planets,
///   stars, meteors, aurora, trails; not a pass, which Pip already
///   catches well);
/// - at most once a week;
/// - and never again once they've said "Not now" twice.
library;

import '../photo/shot_plan.dart' show ShotSubject;

/// Days between mentions.
const proNudgeGapDays = 7;

/// "Not now"s after which it never comes back.
const proNudgeMaxNotNow = 2;

bool showProNudge({
  required bool isPlus,
  required ShotSubject? subject,
  required int catches,
  required DateTime now,
  DateTime? lastShown,
  int notNow = 0,
}) {
  if (isPlus || subject == null || subject == ShotSubject.pass) return false;
  if (catches < 2) return false;
  if (notNow >= proNudgeMaxNotNow) return false;
  if (lastShown != null && now.toUtc().difference(lastShown.toUtc()) < const Duration(days: proNudgeGapDays)) return false;
  return true;
}

/// The one line: what the Pro camera would have done for this.
String proNudgeLine(ShotSubject s) => switch (s) {
      ShotSubject.moon => 'Want the craters sharp? The Pro camera uses the zoom lens and keeps the sharpest of 40 frames.',
      ShotSubject.planet => 'Want it sharper? The Pro camera uses the zoom lens and keeps the steadiest frames.',
      ShotSubject.stars => 'Want more stars? The Pro camera holds the shutter open as long as the sky allows and stacks the frames.',
      ShotSubject.meteors => 'Want to catch a streak? The Pro camera watches every frame and keeps the ones with a meteor.',
      ShotSubject.aurora => 'Want the colour? The Pro camera sets a long exposure, and can run a timelapse all night.',
      ShotSubject.trails => 'Want the whole arc? The Pro camera stacks the frames into one trail.',
      ShotSubject.pass => 'The Pro camera sets the shot up for you.',
    };
