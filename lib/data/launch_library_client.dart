/// Upcoming launches from The Space Devs' Launch Library 2 (free tier:
/// 15 requests/hour; we fetch at most every 6 hours).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/events/launches.dart';
import 'retry.dart';

class LaunchLibraryClient {
  LaunchLibraryClient({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Future<List<Map<String, Object?>>> fetchUpcomingRaw({int limit = 40}) => withRetry(() async {
        final uri = Uri.parse('https://ll.thespacedevs.com/2.3.0/launches/upcoming/?limit=$limit&mode=normal');
        final res = await _client.get(uri, headers: const {'User-Agent': 'LookUp/0.2'}).timeout(const Duration(seconds: 30));
        if (res.statusCode != 200) throw http.ClientException('Launch Library ${res.statusCode}', uri);
        final j = jsonDecode(res.body) as Map<String, Object?>;
        return [for (final r in (j['results'] as List? ?? const [])) (r as Map).cast<String, Object?>()];
      });

  static List<Launch> parse(List<Map<String, Object?>> raw) =>
      [for (final r in raw) ?Launch.fromLaunchLibrary(r)];
}
