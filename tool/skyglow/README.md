# Sky glow map

`assets/sky/skyglow.bin.gz` estimates how bright the night sky is over land,
for "Darker skies nearby" and for guessing a new saved place's sky. It's built
once, offline, by `build_skyglow.py` (needs numpy and Pillow):

```sh
curl -O https://eoimages.gsfc.nasa.gov/images/imagerecords/144000/144897/BlackMarble_2016_3km_gray_geo.tif
curl -O https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_land.geojson
curl -O https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_lakes.geojson
python3 build_skyglow.py BlackMarble_2016_3km_gray_geo.tif ne_50m_land.geojson ne_50m_lakes.geojson ../../assets/sky/skyglow.bin.gz
```

Sources and credits are in `assets/sky/SOURCES-skyglow.txt` (NASA Earth
Observatory imagery, public domain in the US; Natural Earth, public domain).

The script prints how well it fits ten reference skies (rms ~0.4 mag). Known
limits: the NASA image is tone-mapped for display and saturates over whole
metro areas, so inner suburbs read about as bright as downtown, and rural
skies just outside towns read ~0.4 mag too dark. `lib/domain/sky/skyglow.dart`
sets its thresholds on the strict side to compensate. Don't loosen them
without a better source (e.g. the EOG VIIRS annual composites, which need a
free account to download).
