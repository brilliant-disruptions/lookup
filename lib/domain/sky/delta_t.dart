/// ΔT = TT − UT: how far the Earth's slowing spin has put clock time behind
/// the steady time the Sun, Moon and planets keep. About a minute today, half
/// an hour in 1000 AD, three hours at 1 AD. Stars don't care (they're placed
/// by the Earth's turning), but the Moon moves its own width an hour against
/// them, so it needs this to be in the right place on old dates.
///
/// Espenak & Meeus' polynomials, as used for NASA's Five Millennium Canon of
/// eclipses. Before ~700 BC the true value is uncertain by an hour or more.
library;

/// ΔT in seconds for a decimal year (astronomical numbering: 0 = 1 BC).
double deltaTSeconds(double y) {
  if (y < -500) {
    final u = (y - 1820) / 100;
    return -20 + 32 * u * u;
  }
  if (y < 500) {
    final u = y / 100;
    return _poly(u, const [10583.6, -1014.41, 33.78311, -5.952053, -0.1798452, 0.022174192, 0.0090316521]);
  }
  if (y < 1600) {
    final u = (y - 1000) / 100;
    return _poly(u, const [1574.2, -556.01, 71.23472, 0.319781, -0.8503463, -0.005050998, 0.0083572073]);
  }
  if (y < 1700) {
    final t = y - 1600;
    return 120 - 0.9808 * t - 0.01532 * t * t + t * t * t / 7129;
  }
  if (y < 1800) {
    final t = y - 1700;
    return 8.83 + 0.1603 * t - 0.0059285 * t * t + 0.00013336 * t * t * t - t * t * t * t / 1174000;
  }
  if (y < 1860) {
    final t = y - 1800;
    return _poly(t, const [13.72, -0.332447, 0.0068612, 0.0041116, -0.00037436, 0.0000121272, -0.0000001699, 0.000000000875]);
  }
  if (y < 1900) {
    final t = y - 1860;
    return 7.62 + 0.5737 * t - 0.251754 * t * t + 0.01680668 * t * t * t - 0.0004473624 * t * t * t * t + t * t * t * t * t / 233174;
  }
  if (y < 1920) {
    final t = y - 1900;
    return _poly(t, const [-2.79, 1.494119, -0.0598939, 0.0061966, -0.000197]);
  }
  if (y < 1941) {
    final t = y - 1920;
    return _poly(t, const [21.20, 0.84493, -0.076100, 0.0020936]);
  }
  if (y < 1961) {
    final t = y - 1950;
    return 29.07 + 0.407 * t - t * t / 233 + t * t * t / 2547;
  }
  if (y < 1986) {
    final t = y - 1975;
    return 45.45 + 1.067 * t - t * t / 260 - t * t * t / 718;
  }
  if (y < 2005) {
    final t = y - 2000;
    return _poly(t, const [63.86, 0.3345, -0.060374, 0.0017275, 0.000651814, 0.00002373599]);
  }
  if (y < 2050) {
    final t = y - 2000;
    return 62.92 + 0.32217 * t + 0.005589 * t * t;
  }
  final u = (y - 1820) / 100;
  if (y < 2150) return -20 + 32 * u * u - 0.5628 * (2150 - y);
  return -20 + 32 * u * u;
}

double _poly(double x, List<double> c) {
  var r = 0.0;
  for (var i = c.length - 1; i >= 0; i--) {
    r = r * x + c[i];
  }
  return r;
}
