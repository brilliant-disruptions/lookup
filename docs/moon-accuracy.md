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
- **The other body is the weak side.** See below.

## The stars and planets

**Stars** are the J2000 catalogue places, moved by proper motion and
precessed to the date. Annual aberration (Meeus 23.3, pinned to example
23.a) is added only for occultations, where its 20″ matters. Nutation is left
out because it moves the Moon and the star together. The catalogue rounds RA
to 0.001°, so a star is good to ~4″, and against the Moon to ~16″.

**Planets** are still Schlyter's. Their error was measured against Horizons
(geocentric apparent RA/Dec, every 49 h, 2026–2030), relative to our Moon:

| Planet, arcseconds | median | 95% | worst |
|---|---|---|---|
| Mercury | 32 | 62 | 84 |
| Venus | 31 | 53 | 73 |
| Mars | 26 | 67 | 95 |
| Jupiter | 18 | 51 | 65 |
| Saturn | 29 | 96 | 109 |

A light-time correction helped Mercury and Venus but made Saturn worse, so it
was left out. Planet parallax is exact (`planetTopocentric`).

## How a cover is called (`domain/events/occultations.dart`)

| | Margin inside the limb | Error budget |
|---|---|---|
| Stars ≤ mag 2.0 (Aldebaran, Spica, Antares, Pollux, Regulus, Elnath, Alhena) | 1′ | 16″ |
| Planets | 3′ plus the planet's radius (Saturn's rings included) | 121″ |

- **Covers** means the closest approach is at least the margin inside the
  Moon's edge.
- **Near the Moon** means it is within the margin either side of the edge. No
  times are given, because it could be a graze or a miss.
- Otherwise there is no event.
- A contact is only given if it can be seen: Sun ≤ −6° and Moon ≥ 10° up.
- The ± on each time is the error budget over how fast the gap to the edge
  closes there.

## Checked against IOTA

`test/domain/occultations_test.dart` checks against IOTA's archived
predictions from lunar-occultations.com, via the Wayback Machine:

| Event | Sites | Worst difference |
|---|---|---|
| Mars, 8 Dec 2022 | Los Angeles, Denver, Chicago, Phoenix, Seattle, London, Madrid | 19 s |
| Aldebaran, 9 Jan 2017 | Tokyo, Seoul, Taipei | 9 s |
| Spica, 21 Jan 2025 | Dakar, Accra, Lagos, Luanda | 5 s |

Near Aldebaran's southern limit in Taiwan, IOTA has 10–24 minute grazes at
Hualien, Makung and Chiayi. LookUp says "near the Moon" for those, not
"covers". Just outside the path (Kaohsiung) it says near, and far outside
(Manila) nothing. Cairo is in the path but has the Sun up, so LookUp gives
nothing there either.
