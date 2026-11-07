# Is LookUp's Moon good enough for occultations?

**No, not yet.** LookUp shouldn't alert "the Moon covers Saturn at 9:14" on
the Moon it has today. Measured November 2026; pinned by
`test/domain/moon_accuracy_test.dart`.

## What was measured

`moonHorizontal` (Schlyter's Moon plus topocentric parallax) was compared
against JPL Horizons. Horizons gave the topocentric, apparent, airless
azimuth and elevation of the Moon (body 301) every 53 h from 1 Nov 2026 to
1 Nov 2028. That's 332 times at each of four sites: Chicago, London, Sydney
and Quito. The model's geocentric ecliptic position was also compared with
Horizons' (quantity 31), to split the Moon theory's error from the
parallax's.

```
https://ssd.jpl.nasa.gov/api/horizons.api?format=text&COMMAND='301'
  &CENTER='coord@399'&COORD_TYPE='GEODETIC'&SITE_COORD='<lon>,<lat>,<km>'
  &EPHEM_TYPE='OBSERVER'&START_TIME='2026-11-01'&STOP_TIME='2028-11-01'
  &STEP_SIZE='53 h'&QUANTITIES='4'&APPARENT='AIRLESS'&ANG_FORMAT='DEG'
  &CSV_FORMAT='YES'&EXTRA_PREC='YES'&TIME_TYPE='UT'
```

| Error, arcminutes | median | 95% | worst |
|---|---|---|---|
| From the ground, Moon above the horizon (648 rows) | 1.7 | 3.7 | 6.3 |
| From the ground, all rows (1,328) | 1.7 | 3.4 | 6.5 |
| Geocentric (332 rows) | 1.7 | 3.3 | 6.1 |
| along its path (ecliptic longitude) | | | ±5.2 |
| across its path (ecliptic latitude) | | | ±3.2 |

The parallax is handled correctly: it adds under 0.5′. Nearly all of the
error comes from Schlyter's short series for the Moon. Horizons' apparent
places include aberration and nutation (about 0.3′), which LookUp's stars
leave out too, so for a Moon-and-star pair the real error is slightly
smaller than this. The numbers above are on the safe side.

## What that means for an occultation

- **Calling the cover.** The Moon's limb is 14.7–16.7′ from its centre. With
  up to 6.5′ of error in any direction, a cover is only certain when the
  predicted track passes within about 7′ of the centre. That's roughly half
  of the occultations at any one place. A track 8–22′ from centre could
  either cover or miss, which is exactly the call the spec says not to make.
- **The time.** The Moon moves about 0.55′ a minute against the stars, so
  5.2′ along its path is about **±10 minutes** on the disappearance. A
  10-minute heads-up could arrive after the planet has already gone.
  Published predictions (IOTA, USNO) are good to seconds, so a test can't
  pin to them without a tolerance wide enough to hide the problem.

So occultation alerts aren't shipped. The pairings alert ("Saturn near the
Moon") already covers the close approaches honestly.

## What would fix it

Replace Schlyter's Moon with the full series from Meeus, *Astronomical
Algorithms*, chapter 47 (truncated ELP-2000/82, about 60 terms in
longitude and distance and 60 in latitude). Meeus gives it as about 10″ in
longitude and 4″ in latitude. It's still pure Dart with no new data file.

- **Effect.** The disappearance time would be good to about 20 s and the
  margin to about 0.3′, which is occultation grade for a phone alert.
- **What has to be rechecked.** `history_test.dart` (3000 BC – 3000 AD
  against Horizons), the famous nights, eclipses, and the moonrise and
  full-Moon pins.
- **Then.** Re-run this audit before any occultation work starts.
