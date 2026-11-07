# Is LookUp's Moon good enough for occultations?

**Yes, since the Moon moved to Meeus ch. 47.** From the ground it is within
12″ of JPL Horizons. That is enough to say "the Moon covers Saturn" with a
margin and to time it to well under a minute. Measured November 2026;
pinned by `test/domain/moon_accuracy_test.dart`.

## What was measured

`moonHorizontal` was compared against JPL Horizons. Horizons gave the
topocentric, apparent, airless azimuth and elevation of the Moon (body 301)
every 53 h from 1 Nov 2026 to 1 Nov 2028. That's 332 times at each of four
sites: Chicago, London, Sydney and Quito. The model's geocentric ecliptic
position was also compared with Horizons' (quantity 31, with nutation in
longitude added to ours), to split the Moon theory's error from the
parallax's.

```
https://ssd.jpl.nasa.gov/api/horizons.api?format=text&COMMAND='301'
  &CENTER='coord@399'&COORD_TYPE='GEODETIC'&SITE_COORD='<lon>,<lat>,<km>'
  &EPHEM_TYPE='OBSERVER'&START_TIME='2026-11-01'&STOP_TIME='2028-11-01'
  &STEP_SIZE='53 h'&QUANTITIES='4'&APPARENT='AIRLESS'&ANG_FORMAT='DEG'
  &CSV_FORMAT='YES'&EXTRA_PREC='YES'&TIME_TYPE='UT'
```

| Error, arcseconds | median | 95% | worst | before (Schlyter) |
|---|---|---|---|---|
| From the ground, Moon above the horizon (648 rows) | 5.3 | 8.6 | 12.1 | 378 |
| From the ground, all rows (1,328) | 5.3 | 8.5 | 12.1 | 390 |
| Geocentric (332 rows) | 3.9 | 7.7 | 11.5 | 366 |
| along its path (ecliptic longitude) | | | −3.4 to +11.4 | ±312 |
| across its path (ecliptic latitude) | | | −5.0 to +2.7 | ±192 |

## What changed

- **The Moon.** It is now Meeus, *Astronomical Algorithms*, ch. 47 (truncated
  ELP-2000/82): 60 terms in longitude and distance, 60 in latitude.
  Meeus's worked example 47.a is reproduced to 0.1″ in a test.
- **Parallax.** It is exact now. Your position on the WGS 84 ellipsoid is
  subtracted from the Moon's (`moonTopocentric`). Before, it was a
  first-order drop in altitude, which was up to 0.5′ out.
- **Sidereal time.** It is IAU 1982 GMST (Meeus 12.4). Schlyter's version
  was about 21″ out, and that was the floor under every number above. It
  moves the stars by the same amount, so it's pinned too (Meeus example
  12.b).
- **History.** The JPL Horizons pins from 3000 BC to 2400 AD got tighter,
  not looser. Since 1000 BC the Moon is within 0.16° (it was 0.45°);
  before then it is within 0.35° (it was 1.7°).

What's left is mostly the nutation that LookUp leaves out everywhere (up to
about 10″ of where the pole points). It moves the Moon and a star together,
so for "does the Moon cover it" the error is closer to the geocentric
figures.

## What that means for an occultation

- **Calling the cover.** The Moon's limb is 14.7–16.7′ from its centre and
  the Moon is good to 12″. An occultation alert can require the predicted
  track to pass at least ~1′ inside the limb, and still cover nearly every
  real event. Anything closer than that is a graze and is said as "near the
  Moon".
- **The time.** The Moon moves about 0.55′ a minute against the stars, so
  12″ is about **±22 s** on the disappearance. That's fine for a heads-up
  alert, and close enough to pin tests to published IOTA/USNO times.
- **The other body is now the weak side.** The stars are precessed J2000
  places without annual aberration (up to 20″, which has to be added for
  this). The planets are Schlyter's, good to 1–2′, which is ten times worse
  than the Moon. They need their own Horizons check, and a bigger margin or
  a better theory, before a planet occultation is called.
