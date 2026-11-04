/// Distances in the reader's own units: miles where people think in miles
/// (the US, the UK), kilometres everywhere else. Always rounded to a
/// sensible step; never falsely precise.
library;

const kmPerMile = 1.609344;

/// Countries whose people read road distances in miles.
bool countryUsesMiles(String? countryCode) => const {'US', 'GB', 'LR', 'MM', 'PR'}.contains(countryCode?.toUpperCase());

/// To the nearest sensible step: 7, 45, 240.
int roundDistance(double v) => v < 20 ? v.round() : v < 100 ? (v / 5).round() * 5 : (v / 10).round() * 10;

/// "45 km", "30 miles", "1 mile". [km] is always kilometres in.
String distanceWords(double km, {required bool miles}) {
  final n = roundDistance(miles ? km / kmPerMile : km);
  if (!miles) return '$n km';
  return n == 1 ? '1 mile' : '$n miles';
}
