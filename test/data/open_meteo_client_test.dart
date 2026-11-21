import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lookup/data/open_meteo_client.dart';
import 'package:lookup/domain/privacy/rough_place.dart';

void main() {
  test('a coordinate is rounded to two places: about a kilometre', () {
    expect(roughCoord(36.16589), 36.17);
    expect(roughCoord(-86.78444), -86.78);
    expect(roughCoord(-0.004), 0);
    expect(roughCoord(51.5), 51.5);
  });

  // Info.plist and the privacy page promise only a rough place leaves the phone.
  test('the weather service is sent the rough place, never the fix', () async {
    late Uri asked;
    final c = OpenMeteoClient(
      client: MockClient((r) async {
        asked = r.url;
        return http.Response('{"hourly":{"time":[],"cloud_cover":[]}}', 200);
      }),
    );
    try {
      await c.fetchCloudForecast(36.16589, -86.78444);
    } catch (_) {
      // Only what was asked matters here.
    }
    expect(asked.queryParameters['latitude'], '36.17');
    expect(asked.queryParameters['longitude'], '-86.78');
    expect(asked.toString(), isNot(contains('36.165')));
  });
}
