/// Place search, all on the phone: the GeoNames towns of 5,000+ people
/// (assets/sky/towns.json.gz, built by tool/places/build.py; see
/// assets/sky/SOURCES-towns.txt). Nothing typed here leaves the phone.
///
/// A town matches when its name starts with what was typed, or one of its
/// words does, ignoring case and accents ("sao paulo", "zurich", "tromso").
/// After a comma the rest narrows by region or country ("Springfield, Ill").
/// Exact names first, then names that start with it, then a later word;
/// bigger towns first within each.
library;

import '../models/settings.dart';

class Town {
  Town({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.population,
    this.region = '',
    this.country = '',
    String ascii = '',
  }) : _keys = {foldForSearch(name), if (ascii.isNotEmpty) foldForSearch(ascii)}.toList(growable: false),
       _where = foldForSearch('$region $country');

  final String name;
  final double latitude;
  final double longitude;
  final int population;
  final String region;
  final String country;
  final List<String> _keys;
  final String _where;

  /// "Tennessee, United States": what tells two Springfields apart.
  String get detail => [region, country].where((s) => s.isNotEmpty).join(', ');

  SavedPlace get place => SavedPlace(name: name, latitude: latitude, longitude: longitude);

  /// One row of the asset: [name, ascii or "", lat, lon, population,
  /// region, country]. Null for a row that isn't one.
  static Town? fromRow(Object? r) {
    if (r is! List || r.length < 7) return null;
    final [name, ascii, lat, lon, pop, region, country, ...] = r;
    if (name is! String || name.isEmpty || lat is! num || lon is! num) return null;
    return Town(
      name: name,
      ascii: ascii is String ? ascii : '',
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      population: pop is num ? pop.toInt() : 0,
      region: region is String ? region : '',
      country: country is String ? country : '',
    );
  }
}

class TownIndex {
  TownIndex(Iterable<Town> towns) : _towns = [...towns]..sort((a, b) => b.population.compareTo(a.population));

  factory TownIndex.fromRows(List<Object?> rows) => TownIndex([for (final r in rows) ?Town.fromRow(r)]);

  final List<Town> _towns;
  int get length => _towns.length;

  /// Up to [limit] towns for [query]; nothing under two letters.
  List<({SavedPlace place, String detail})> search(String query, {int limit = 8}) {
    final comma = query.indexOf(',');
    final q = foldForSearch(comma < 0 ? query : query.substring(0, comma));
    final within = comma < 0 ? '' : foldForSearch(query.substring(comma + 1));
    if (q.length < 2) return const [];
    // Three tiers, each already in population order.
    final exact = <Town>[], starts = <Town>[], word = <Town>[];
    for (final t in _towns) {
      if (within.isNotEmpty && !_hasWordStarting(t._where, within)) continue;
      var tier = 3;
      for (final k in t._keys) {
        if (k == q) {
          tier = 0;
        } else if (k.startsWith(q)) {
          if (tier > 1) tier = 1;
        } else if (tier > 2 && _hasWordStarting(k, q)) {
          tier = 2;
        }
      }
      switch (tier) {
        case 0:
          exact.add(t);
        case 1:
          if (exact.length + starts.length < limit) starts.add(t);
        case 2:
          if (exact.length + starts.length + word.length < limit) word.add(t);
      }
    }
    return [for (final t in [...exact, ...starts, ...word].take(limit)) (place: t.place, detail: t.detail)];
  }

  static bool _hasWordStarting(String s, String q) {
    if (s.startsWith(q)) return true;
    for (var i = s.indexOf(' '); i >= 0; i = s.indexOf(' ', i + 1)) {
      if (s.startsWith(q, i + 1)) return true;
    }
    return false;
  }
}

/// Lower case, accents off, punctuation and runs of spaces to one space:
/// "Saint-Étienne" and "saint etienne" read the same.
String foldForSearch(String s) {
  final b = StringBuffer();
  var space = true;
  for (final r in s.toLowerCase().runes) {
    final c = String.fromCharCode(r);
    final f = _fold[c] ?? c;
    final isWord = f.runes.every((x) => x > 127 || (x >= 0x30 && x <= 0x39) || (x >= 0x61 && x <= 0x7a));
    if (!isWord) {
      if (!space) b.write(' ');
      space = true;
      continue;
    }
    b.write(f);
    space = false;
  }
  return b.toString().trimRight();
}

final Map<String, String> _fold = () {
  const groups = {
    'a': 'àáâãäåāăąǎ',
    'ae': 'æ',
    'c': 'çćĉċč',
    'd': 'ďđð',
    'e': 'èéêëēĕėęě',
    'g': 'ĝğġģ',
    'h': 'ĥħ',
    'i': 'ìíîïĩīĭįı',
    'j': 'ĵ',
    'k': 'ķ',
    'l': 'ĺļľŀł',
    'n': 'ñńņňŉ',
    'o': 'òóôõöøōŏőǒ',
    'oe': 'œ',
    'r': 'ŕŗř',
    's': 'śŝşšș',
    'ss': 'ß',
    't': 'ţťŧț',
    'th': 'þ',
    'u': 'ùúûüũūŭůűųǔ',
    'w': 'ŵ',
    'y': 'ýÿŷ',
    'z': 'źżž',
    '': "'’‘ʻ`",
  };
  return {
    for (final e in groups.entries)
      for (final c in e.value.runes) String.fromCharCode(c): e.key,
  };
}();
