/// "Look up with me" links (relay/src/invite.ts): the app sends what's
/// happening and the "where to look" picture, and gets back a short link
/// that unfurls into a card in Messages, with Add to calendar and Add to
/// Apple Wallet behind it. Only when this build knows a relay
/// (`LOOKUP_RELAY_URL`); otherwise invites go out as a picture and a
/// calendar file, as before.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'aurora_reports_client.dart' show relayUrl;

class InviteClient {
  InviteClient({http.Client? client, String base = relayUrl})
      : _client = client ?? http.Client(),
        _base = base.endsWith('/') ? base.substring(0, base.length - 1) : base;

  final http.Client _client;
  final String _base;

  /// The link for an invite, or null when the relay said no or couldn't be
  /// reached in time: the caller falls back to sending a picture.
  Future<Uri?> create(Map<String, Object?> fields, {List<int>? image}) async {
    if (_base.isEmpty) return null;
    try {
      final res = await _client
          .post(Uri.parse('$_base/v1/invites'),
              headers: const {'content-type': 'application/json', 'User-Agent': 'LookUp/0.1'},
              body: jsonEncode({
                for (final MapEntry(:key, :value) in fields.entries) key: ?value,
                'image': ?(image == null ? null : base64Encode(image)),
              }))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 201) return null;
      final url = (jsonDecode(res.body) as Map)['url'];
      return url is String ? Uri.tryParse(url) : null;
    } catch (_) {
      return null;
    }
  }
}

/// Keeps a place name to what the invite page accepts (letters, digits,
/// spaces and simple punctuation, 48 characters); null when nothing's left.
String? invitePlace(String? place) {
  if (place == null) return null;
  final clean = place.replaceAll(RegExp(r"[^\p{L}\p{N} .,'’()\-]", unicode: true), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (clean.isEmpty) return null;
  return clean.length <= 48 ? clean : clean.substring(0, 48).trim();
}
