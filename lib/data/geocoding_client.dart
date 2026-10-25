/// Place search for saved places (Open-Meteo geocoding; free, no key,
/// non-commercial like the forecast).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/models/settings.dart';

class GeocodingClient {
  GeocodingClient({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Future<List<({SavedPlace place, String detail})>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {'name': q, 'count': '8', 'format': 'json'});
    final res = await _client.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw http.ClientException('Geocoding ${res.statusCode}', uri);
    return parse(jsonDecode(res.body));
  }

  static List<({SavedPlace place, String detail})> parse(Object? decoded) {
    final results = decoded is Map ? decoded['results'] : null;
    if (results is! List) return const [];
    return [
      for (final r in results.whereType<Map>())
        if (r['latitude'] is num && r['longitude'] is num)
          (
            place: SavedPlace(
              name: '${r['name']}',
              latitude: (r['latitude'] as num).toDouble(),
              longitude: (r['longitude'] as num).toDouble(),
            ),
            detail: [r['admin1'], r['country']].whereType<String>().join(', '),
          ),
    ];
  }
}
