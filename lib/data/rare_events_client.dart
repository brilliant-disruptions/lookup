/// The relay's curated list of rare comets and novae
/// (`GET /v1/rare-events`, relay/src/rare_events.ts). Asked at most once a
/// day; without LOOKUP_RELAY_URL it's never asked.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'aurora_reports_client.dart' show relayUrl;
import 'retry.dart';

class RareEventsClient {
  RareEventsClient({http.Client? client, String base = relayUrl})
      : _client = client ?? http.Client(),
        _base = base.endsWith('/') ? base.substring(0, base.length - 1) : base;

  final http.Client _client;
  final String _base;

  /// The decoded `{now, events: [...]}`; parse with `parseRareEvents`.
  Future<Object?> fetchRaw() => withRetry(() async {
        final uri = Uri.parse('$_base/v1/rare-events');
        final res = await _client.get(uri, headers: const {'User-Agent': 'LookUp/0.1'}).timeout(const Duration(seconds: 20));
        if (res.statusCode != 200) throw http.ClientException('Relay ${res.statusCode}', uri);
        return jsonDecode(res.body);
      });
}
