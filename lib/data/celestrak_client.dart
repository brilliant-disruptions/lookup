/// Celestrak GP data (OMM JSON). Be polite: callers cache for ≥ 24 h.
library;

import 'package:http/http.dart' as http;

import 'decode.dart';
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

  /// The ~150 brightest objects (Celestrak's "visual" group), for the
  /// satellites-tonight list. Fetched on demand, at most daily.
  Future<List<OmmRecord>> fetchVisual() => _get('$_base/gp.php?GROUP=visual&FORMAT=json');

  // A refusal is an answer, not a glitch: asking again would only add to
  // whatever made Celestrak refuse.
  Future<List<OmmRecord>> _get(String url) =>
      withRetry(() => _getOnce(url), retryIf: (e) => e is! CelestrakRefused);

  Future<List<OmmRecord>> _getOnce(String url) async {
    final res = await _client
        .get(Uri.parse(url), headers: const {'User-Agent': 'LookUp/0.1'})
        .timeout(const Duration(seconds: 60));
    if (res.statusCode >= 400 && res.statusCode < 500) throw CelestrakRefused(res.statusCode, Uri.parse(url));
    if (res.statusCode != 200) {
      throw http.ClientException('Celestrak ${res.statusCode}', Uri.parse(url));
    }
    return decodeJson(res.body, OmmRecord.listFromJson);
  }
}

/// Celestrak said no (403 blocked, 429 too many, 404 gone): never retried,
/// and the feed rests a day ([LocalStore.celestrakDue]).
class CelestrakRefused extends http.ClientException {
  CelestrakRefused(this.statusCode, Uri url) : super('Celestrak $statusCode', url);
  final int statusCode;
}
