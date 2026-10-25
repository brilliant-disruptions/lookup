/// Optional LookUp backend (Supabase Edge Functions). Everything works
/// without it; with it, phones get trimmed orbit bundles, timely aurora
/// pushes, verified purchases and anonymous metrics.
///
/// Configure at build time with `--dart-define=LOOKUP_SUPABASE_URL=...` and
/// `--dart-define=LOOKUP_SUPABASE_ANON_KEY=...` (see docs/backend.md).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/orbit/omm.dart';
import 'retry.dart';

class BackendConfig {
  const BackendConfig({required this.url, required this.anonKey});
  final String url;
  final String anonKey;

  static BackendConfig? fromEnvironment() {
    const url = String.fromEnvironment('LOOKUP_SUPABASE_URL');
    const key = String.fromEnvironment('LOOKUP_SUPABASE_ANON_KEY');
    if (url.isEmpty || key.isEmpty) return null;
    return const BackendConfig(url: url, anonKey: key);
  }

  Uri fn(String name) => Uri.parse('$url/functions/v1/$name');
  Map<String, String> get headers => {
        'authorization': 'Bearer $anonKey',
        'apikey': anonKey,
        'content-type': 'application/json',
      };
}

class OrbitBundle {
  const OrbitBundle({required this.fetchedAt, required this.iss, required this.tiangong, required this.starlink, required this.launchesRaw});
  final DateTime fetchedAt;
  final List<OmmRecord> iss;
  final List<OmmRecord> tiangong;
  final List<OmmRecord> starlink;
  final List<Map<String, Object?>> launchesRaw;

  factory OrbitBundle.fromJson(Map<String, Object?> j) => OrbitBundle(
        fetchedAt: DateTime.tryParse('${j['fetchedAt']}')?.toUtc() ?? DateTime.now().toUtc(),
        iss: OmmRecord.listFromJson(j['iss']),
        tiangong: OmmRecord.listFromJson(j['tiangong']),
        starlink: OmmRecord.listFromJson(j['starlink']),
        launchesRaw: [for (final r in (j['launches'] as List? ?? const [])) (r as Map).cast<String, Object?>()],
      );
}

class BackendClient {
  BackendClient(this.config, {http.Client? client}) : _client = client ?? http.Client();
  final BackendConfig config;
  final http.Client _client;

  Future<OrbitBundle> orbits() => withRetry(() async {
        final res = await _client.get(config.fn('orbits'), headers: config.headers).timeout(const Duration(seconds: 30));
        if (res.statusCode != 200) throw http.ClientException('orbits ${res.statusCode}', config.fn('orbits'));
        return OrbitBundle.fromJson((jsonDecode(res.body) as Map).cast());
      });

  Future<void> registerDevice(Map<String, Object?> body) async {
    final res = await _client.post(config.fn('register-device'), headers: config.headers, body: jsonEncode(body)).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw http.ClientException('register ${res.statusCode}: ${res.body}', config.fn('register-device'));
  }

  Future<void> track(String installId, List<Map<String, Object?>> events) async {
    final res = await _client
        .post(config.fn('track'), headers: config.headers, body: jsonEncode({'installId': installId, 'events': events}))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw http.ClientException('track ${res.statusCode}', config.fn('track'));
  }

  /// Returns {active, productId, expiresAt} from the store, verified server-side.
  Future<Map<String, Object?>> verifyReceipt(Map<String, Object?> body) async {
    final res = await _client.post(config.fn('verify-receipt'), headers: config.headers, body: jsonEncode(body)).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw http.ClientException('verify ${res.statusCode}: ${res.body}', config.fn('verify-receipt'));
    return (jsonDecode(res.body) as Map).cast();
  }
}
