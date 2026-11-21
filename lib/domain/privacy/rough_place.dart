/// What LookUp lets out of the phone about where you are.
library;

/// A coordinate to two decimal places (about a kilometre): what goes to the
/// weather service and what's stamped on a picture. The sky maths keeps the
/// real one, which never leaves the phone.
double roughCoord(double deg) => (deg * 100).roundToDouble() / 100;
