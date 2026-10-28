import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/data/geocoding_client.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/sky/visibility.dart';

void main() {
  const home = SavedPlace(name: 'Home', latitude: 36.1659, longitude: -86.7844);
  const cabin = SavedPlace(name: 'Cabin', latitude: 35.6118, longitude: -83.4895);

  test('using a place pins it, saves it once and reports it active', () {
    var s = const LookUpSettings();
    expect(s.activePlace, isNull);
    s = s.usePlace(home).usePlace(cabin).usePlace(home);
    expect(s.places.map((p) => p.name), ['Home', 'Cabin']);
    expect(s.locationMode, LocationMode.pinned);
    expect(s.latitude, home.latitude);
    expect(s.activePlace?.name, 'Home');
    expect(s.copyWith(locationMode: LocationMode.auto).activePlace, isNull);
  });

  test('places survive a JSON round trip; old settings without them load', () {
    final s = const LookUpSettings().usePlace(home).usePlace(cabin);
    final rt = LookUpSettings.fromJson(s.toJson());
    expect(rt.places.map((p) => (p.name, p.latitude, p.longitude)),
        s.places.map((p) => (p.name, p.latitude, p.longitude)));
    expect(rt.activePlace?.name, 'Cabin');
    expect(LookUpSettings.fromJson(const {}).places, isEmpty);
  });

  test('geocoding results parse to places with a region line', () {
    final r = GeocodingClient.parse({
      'results': [
        {'name': 'Nashville', 'latitude': 36.16589, 'longitude': -86.78444, 'admin1': 'Tennessee', 'country': 'United States'},
        {'name': 'Broken'},
      ],
    });
    expect(r, hasLength(1));
    expect(r.single.place.name, 'Nashville');
    expect(r.single.detail, 'Tennessee, United States');
    expect(GeocodingClient.parse({'generationtime_ms': 0.5}), isEmpty);
  });

  test('a place can say how dark its sky is, and keeps it through JSON and use', () {
    final dark = cabin.withDarkness(SkyDarkness.dark);
    final s = const LookUpSettings().usePlace(dark);
    final back = LookUpSettings.fromJson(s.toJson());
    expect(back.places.single.skyDarkness, SkyDarkness.dark);
    expect(back.activePlace?.skyDarkness, SkyDarkness.dark);
    // Older saved places have no darkness and still load.
    expect(SavedPlace.fromJson({'n': 'Old', 'la': 1.0, 'lo': 2.0}).skyDarkness, isNull);
  });

  test('favourites toggle on and off, keep their order and survive JSON', () {
    var s = const LookUpSettings();
    s = s.toggleFavourite('planet:saturn').toggleFavourite('m31').toggleFavourite('moon');
    expect(s.favourites, ['planet:saturn', 'm31', 'moon']);
    expect(s.isFavourite('m31'), isTrue);
    s = s.toggleFavourite('m31');
    expect(s.favourites, ['planet:saturn', 'moon']);
    expect(LookUpSettings.fromJson(s.toJson()).favourites, ['planet:saturn', 'moon']);
    expect(LookUpSettings.fromJson(const {}).favourites, isEmpty);
  });

  test('the tour is shown once: existing installs get it, and it is remembered', () {
    expect(LookUpSettings.fromJson(const {'onboarded': true}).toured, isFalse);
    final seen = const LookUpSettings().copyWith(toured: true);
    expect(LookUpSettings.fromJson(seen.toJson()).toured, isTrue);
  });

  test('one saved place free; LookUp+ saves any number; nobody loses places they had', () {
    const home = SavedPlace(name: 'Home', latitude: 36.17, longitude: -86.78);
    const cabin = SavedPlace(name: 'Cabin', latitude: 35.61, longitude: -83.49);
    const free = LookUpSettings();
    expect(free.canSave(home), isTrue);
    final one = free.copyWith(places: [home]);
    expect(one.canSave(cabin), isFalse);
    expect(one.canSave(home), isTrue, reason: 'already saved');
    expect(one.copyWith(isPlus: true).canSave(cabin), isTrue);
    // Saved before the limit: kept, and still usable.
    final grandfathered = free.copyWith(places: [home, cabin]);
    expect(grandfathered.usePlace(cabin).places, hasLength(2));
  });
}
