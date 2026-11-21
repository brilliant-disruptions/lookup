/// What LookUp gives everyone and what LookUp+ adds, in one place. Pure.
///
/// Free is the hook and stays genuinely useful: space station alerts (cloud
/// checked), meteor showers, lunar and solar eclipses, planet pairings, the
/// full Moon rising, new stars (novae), the sky map, tonight's verdict and
/// the log. LookUp+ is "never miss anything up there": every kind of alert,
/// where to go tonight, the whole fortnight ahead at any saved place, as many
/// places as you like, and photo planning.
library;

enum PlusFeature {
  /// Starlink trains, Tiangong, rocket launches, live aurora alerts (with
  /// "Seen near you"), bright comets and the Moon covering a bright star or
  /// planet. Which event types these are is `SkyEventType.plusOnly`.
  alerts,

  /// Where to go tonight: clearer, darker skies near you.
  whereToGo,

  /// Planning nights beyond the first few.
  planAhead,

  /// More than one saved place.
  places,

  /// The station crossing the Sun or Moon (photo planning).
  transits,

  /// The Pro camera: the right lens, shutter and ISO for the Moon, planets,
  /// stars, meteors and aurora, stacked long exposures, Catch it for passes,
  /// and timelapses that start and stop by themselves. Pip's quick catch
  /// (point, tap, logged) stays free: it's how anyone fills their Log.
  camera,

  /// The sky through history: free goes a week either side of now and to a
  /// few famous nights; LookUp+ goes anywhere from 3000 BC to 3000 AD.
  history,

  /// Photos without the "LookUp" caption along the foot. Free keeps it:
  /// every shared catch says where it came from.
  noCaption,
}

abstract final class FreePlan {
  /// Tonight and the next two nights.
  static const nightsAhead = 3;

  /// One saved place (home, say); following the phone is always free.
  static const savedPlaces = 1;

  static bool canPlanNight(int night, {required bool isPlus}) => isPlus || night < nightsAhead;

  static bool canAddPlace(int saved, {required bool isPlus}) => isPlus || saved < savedPlaces;

  /// How far either side of now free can take the sky.
  static const historyDays = 7;

  /// The famous nights free can visit: one ancient, one science, one space.
  static const freeFamousNights = {'giza', 'galileo', 'apollo11'};

  static bool canVisit(DateTime utc, DateTime now, {required bool isPlus}) =>
      isPlus || utc.toUtc().difference(now.toUtc()).abs() <= const Duration(days: historyDays);

  static bool canVisitFamous(String id, {required bool isPlus}) => isPlus || freeFamousNights.contains(id);

  /// Whether a photo gets the "LookUp" caption: always on free.
  static bool caption({required bool isPlus, required bool wanted}) => !isPlus || wanted;

  /// Features that are all-or-nothing on free.
  static bool canUse(PlusFeature f, {required bool isPlus}) =>
      isPlus ||
      switch (f) {
        PlusFeature.whereToGo || PlusFeature.transits || PlusFeature.alerts || PlusFeature.camera || PlusFeature.noCaption => false,
        // Limited rather than locked; see canPlanNight / canAddPlace / canVisit.
        PlusFeature.planAhead || PlusFeature.places || PlusFeature.history => true,
      };
}
