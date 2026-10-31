/// What LookUp gives everyone and what LookUp+ adds, in one place. Pure.
///
/// Free is the hook and stays genuinely useful: space station alerts (cloud
/// checked), meteor showers, lunar and solar eclipses, planet pairings, the
/// sky map, tonight's verdict and the log. LookUp+ is "never miss anything
/// up there": every kind of alert, where to go tonight, the whole fortnight
/// ahead at any saved place, as many places as you like, and photo planning.
library;

enum PlusFeature {
  /// Starlink trains, Tiangong, rocket launches and live aurora alerts.
  alerts,

  /// Where to go tonight: clearer, darker skies near you.
  whereToGo,

  /// Planning nights beyond the first few.
  planAhead,

  /// More than one saved place.
  places,

  /// The station crossing the Sun or Moon (photo planning).
  transits,
}

abstract final class FreePlan {
  /// Tonight and the next two nights.
  static const nightsAhead = 3;

  /// One saved place (home, say); following the phone is always free.
  static const savedPlaces = 1;

  static bool canPlanNight(int night, {required bool isPlus}) => isPlus || night < nightsAhead;

  static bool canAddPlace(int saved, {required bool isPlus}) => isPlus || saved < savedPlaces;

  /// Features that are all-or-nothing on free.
  static bool canUse(PlusFeature f, {required bool isPlus}) =>
      isPlus ||
      switch (f) {
        PlusFeature.whereToGo || PlusFeature.transits || PlusFeature.alerts => false,
        // Limited rather than locked; see canPlanNight / canAddPlace.
        PlusFeature.planAhead || PlusFeature.places => true,
      };
}
