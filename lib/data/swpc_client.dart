/// NOAA Space Weather Prediction Center feeds.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'retry.dart';

import '../domain/aurora/aurora_rules.dart';

class SwpcClient {
  SwpcClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _base = 'https://services.swpc.noaa.gov';

  /// Latest 1-minute estimated Kp.
  Future<double?> fetchEstimatedKpNow() async {
    final list = await _getJson('$_base/json/planetary_k_index_1m.json');
    if (list is! List || list.isEmpty) return null;
    final last = list.last as Map;
    return (last['estimated_kp'] as num?)?.toDouble() ??
        (last['kp_index'] as num?)?.toDouble();
  }

  /// 3-hour Kp: recent observed + 3-day predicted.
  Future<List<KpForecastPoint>> fetchKpForecast() async {
    final list =
        await _getJson('$_base/products/noaa-planetary-k-index-forecast.json');
    if (list is! List) return const [];
    return [
      for (final e in list)
        if (e is Map && e['time_tag'] is String && e['kp'] is num)
          KpForecastPoint(
            time: DateTime.parse('${e['time_tag']}Z').toUtc(),
            kp: (e['kp'] as num).toDouble(),
            kind: e['observed'] as String? ?? 'predicted',
          ),
    ];
  }

  /// Ovation aurora probability (0–100) at the grid cell containing the
  /// location. The grid is ~900 KB; we decode and sample, never store it.
  Future<int> fetchOvationProbabilityAt(double lat, double lon) async {
    final j = await _getJson('$_base/json/ovation_aurora_latest.json');
    if (j is! Map || j['coordinates'] is! List) return 0;
    return ovationProbabilityAt(j['coordinates'] as List, lat, lon);
  }

  Future<Object?> _getJson(String url) => withRetry(() => _getJsonOnce(url));

  Future<Object?> _getJsonOnce(String url) async {
    final res = await _client
        .get(Uri.parse(url), headers: const {'User-Agent': 'LookUp/0.1'})
        .timeout(const Duration(seconds: 45));
    if (res.statusCode != 200) {
      throw http.ClientException('SWPC ${res.statusCode}', Uri.parse(url));
    }
    return jsonDecode(res.body);
  }
}
