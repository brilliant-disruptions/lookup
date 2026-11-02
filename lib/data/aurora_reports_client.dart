/// The Seen near you relay (relay/, docs/seen-near-you.md): send an "I can
/// see it", read what people nearby reported, sign up to be woken.
///
/// The relay's address comes in at build time:
/// `--dart-define=LOOKUP_RELAY_URL=https://…`. Without it the feature is
/// hidden and nothing is ever sent.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/aurora/seen_nearby.dart';
import 'retry.dart';

const relayUrl = String.fromEnvironment('LOOKUP_RELAY_URL');

/// Whether this build knows a relay at all.
bool get relayConfigured => relayUrl.isNotEmpty;

typedef ReportCell = ({double lat, double lon});

class AuroraReportsClient {
  AuroraReportsClient({http.Client? client, String base = relayUrl})
      : _client = client ?? http.Client(),
        _base = base.endsWith('/') ? base.substring(0, base.length - 1) : base;

  final http.Client _client;
  final String _base;
  static const _headers = {'content-type': 'application/json', 'User-Agent': 'LookUp/0.1'};

  Uri _u(String path, [Map<String, String>? query]) => Uri.parse('$_base$path').replace(queryParameters: query);

  /// "I can see it", filed under the half-degree cell around [latDeg],
  /// [lonDeg] ([reportCell]): the position itself never leaves the phone.
  /// False when the relay turned it down (e.g. reported a moment ago).
  Future<bool> report({required double latDeg, required double lonDeg, required SeenHow how, required String reporter}) async {
    final c = reportCell(latDeg, lonDeg);
    final res = await _client
        .post(_u('/v1/report'),
            headers: _headers,
            body: jsonEncode({
              'cell': {'la': c.lat, 'lo': c.lon},
              'how': how.name,
              'reporter': reporter,
            }))
        .timeout(const Duration(seconds: 20));
    return res.statusCode == 202;
  }

  /// What people within [radiusKm] reported in the last twenty minutes.
  Future<List<AuroraReport>> nearby(double latDeg, double lonDeg, {double radiusKm = 250}) => withRetry(() async {
        final cells = cellsNear(latDeg, lonDeg, radiusKm: radiusKm);
        final res = await _client
            .get(_u('/v1/reports', {'cells': _cellsParam(cells)}), headers: _headers)
            .timeout(const Duration(seconds: 20));
        if (res.statusCode != 200) throw http.ClientException('relay ${res.statusCode}', res.request?.url);
        final j = jsonDecode(res.body) as Map<String, Object?>;
        return [
          for (final r in (j['reports'] as List? ?? const []))
            if (r is Map) AuroraReport.fromJson(r.cast<String, Object?>()),
        ];
      });

  /// Be woken when people near [latDeg], [lonDeg] see it. [token] is the
  /// APNs device token or FCM registration token.
  Future<void> subscribe({
    required String token,
    required bool apple,
    required double latDeg,
    required double lonDeg,
    bool sandbox = false,
  }) async {
    final cells = cellsNear(latDeg, lonDeg);
    final res = await _client
        .post(_u('/v1/subscribe'),
            headers: _headers,
            body: jsonEncode({
              'token': token,
              'platform': apple ? 'apns' : 'fcm',
              'sandbox': sandbox,
              'cells': [for (final c in cells) {'la': c.lat, 'lo': c.lon}],
            }))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 204) throw http.ClientException('relay ${res.statusCode}', res.request?.url);
  }

  Future<void> unsubscribe(String token) async {
    final req = http.Request('DELETE', _u('/v1/subscribe'))
      ..headers.addAll(_headers)
      ..body = jsonEncode({'token': token});
    await _client.send(req).timeout(const Duration(seconds: 20));
  }

  static String _cellsParam(List<ReportCell> cells) => [for (final c in cells) '${c.lat},${c.lon}'].join(';');
}
