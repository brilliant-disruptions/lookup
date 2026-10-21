/// Open-Meteo hourly cloud cover. Free for non-commercial use; switch to the
/// commercial plan (or another provider) the month the app charges.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/weather/cloud_forecast.dart';

class OpenMeteoClient {
  OpenMeteoClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<CloudForecast> fetchCloudForecast(double lat, double lon,
      {int days = 7}) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': lat.toStringAsFixed(4),
      'longitude': lon.toStringAsFixed(4),
      'hourly': 'cloud_cover',
      'forecast_days': '$days',
      'timeformat': 'unixtime',
      'timezone': 'UTC',
    });
    final res = await _client.get(uri).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw http.ClientException('Open-Meteo ${res.statusCode}', uri);
    }
    return parseCloudForecast(jsonDecode(res.body) as Map<String, Object?>,
        latitude: lat, longitude: lon, fetchedAt: DateTime.now().toUtc());
  }

  static CloudForecast parseCloudForecast(Map<String, Object?> j,
      {required double latitude,
      required double longitude,
      required DateTime fetchedAt}) {
    final hourly = j['hourly'] as Map?;
    final times = (hourly?['time'] as List?) ?? const [];
    final cover = (hourly?['cloud_cover'] as List?) ?? const [];
    final n = times.length < cover.length ? times.length : cover.length;
    return CloudForecast(
      latitude: latitude,
      longitude: longitude,
      fetchedAt: fetchedAt,
      hourly: [
        for (var i = 0; i < n; i++)
          if (cover[i] is num)
            CloudSample(
              time: DateTime.fromMillisecondsSinceEpoch(
                  (times[i] as num).toInt() * 1000,
                  isUtc: true),
              coverPercent: (cover[i] as num).round(),
            ),
      ],
    );
  }
}
