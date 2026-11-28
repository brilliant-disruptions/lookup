/// Clouds, fog and rain from the relay (`GET /v1/clouds`, relay/src/met.ts),
/// which asks MET Norway's Locationforecast on our behalf and keeps to its
/// terms. The phone never calls MET itself.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/privacy/rough_place.dart';
import '../domain/weather/cloud_forecast.dart';
import '../domain/weather/met_steps.dart';
import 'relay_config.dart';
import 'retry.dart';

/// The relay said no for a reason a retry won't fix (bad place, paused,
/// busy), or there is no relay in this build.
class CloudsUnavailable implements Exception {
  const CloudsUnavailable(this.why);
  final String why;
  @override
  String toString() => 'Clouds unavailable: $why';
}

class CloudsClient {
  CloudsClient({http.Client? client, String base = relayUrl, DateTime Function()? now})
      : _client = client ?? http.Client(),
        _base = base.endsWith('/') ? base.substring(0, base.length - 1) : base,
        _now = now ?? DateTime.now;

  final http.Client _client;
  final String _base;
  final DateTime Function() _now;
  static const _headers = {'accept': 'application/json', 'User-Agent': 'LookUp/1.0'};

  /// The forecast for about where [lat], [lon] is. Throws when there's
  /// none: callers keep what they had, or have no clouds (unknown, never
  /// clear).
  Future<CloudForecast> fetch(double lat, double lon) {
    if (_base.isEmpty) return Future.error(const CloudsUnavailable('no relay in this build'));
    // 4xx and 503 (paused, busy) won't change in two seconds: no retry.
    return withRetry(() => _fetchOnce(lat, lon), retryIf: (e) => e is! CloudsUnavailable);
  }

  Future<CloudForecast> _fetchOnce(double lat, double lon) async {
    final uri = Uri.parse('$_base/v1/clouds').replace(queryParameters: {
      // To about a kilometre: all a forecast grid needs, and all that
      // leaves the phone (the privacy page and Info.plist say "rough").
      'lat': roughCoord(lat).toStringAsFixed(2),
      'lon': roughCoord(lon).toStringAsFixed(2),
    });
    final res = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
    if (res.statusCode == 503 || (res.statusCode >= 400 && res.statusCode < 500)) {
      throw CloudsUnavailable('relay ${res.statusCode}');
    }
    if (res.statusCode != 200) throw http.ClientException('Clouds ${res.statusCode}', uri);
    final f = forecastFromRelay(jsonDecode(res.body) as Map<String, Object?>,
        latitude: lat, longitude: lon, now: _now().toUtc());
    if (f.hourly.isEmpty) throw const CloudsUnavailable('empty forecast');
    return f;
  }
}
