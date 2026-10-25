import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/data/geocoding_client.dart';
import 'package:lookup/domain/models/settings.dart';

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
}
