/// Celestrak GP data (OMM JSON). Be polite: callers cache for ≥ 24 h.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'retry.dart';

import '../domain/orbit/omm.dart';

class CelestrakClient {
  CelestrakClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _base = 'https://celestrak.org/NORAD/elements';

  Future<List<OmmRecord>> fetchByCatalogNumber(int catnr) =>
      _get('$_base/gp.php?CATNR=$catnr&FORMAT=json');

  /// Whole Starlink catalog (~11 k objects, ~4.7 MB). Daily, Wi-Fi preferred.
  Future<List<OmmRecord>> fetchStarlink() =>
      _get('$_base/gp.php?GROUP=starlink&FORMAT=json');

  /// SpaceX-provided ephemerides: covers just-launched batches before they
  /// appear in the public catalog.
  Future<List<OmmRecord>> fetchStarlinkSupplemental() =>
      _get('$_base/supplemental/sup-gp.php?FILE=starlink&FORMAT=json');

  Future<List<OmmRecord>> _get(String url) => withRetry(() => _getOnce(url));

  Future<List<OmmRecord>> _getOnce(String url) async {
    final res = await _client
        .get(Uri.parse(url), headers: const {'User-Agent': 'LookUp/0.1'})
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      throw http.ClientException('Celestrak ${res.statusCode}', Uri.parse(url));
    }
    return OmmRecord.listFromJson(jsonDecode(res.body));
  }
}
