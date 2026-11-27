/// The bundled town list for place search (assets/sky/towns.json.gz,
/// about 1.6 MB), read once, off the main thread, and kept.
library;

import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:isolate';

import 'package:flutter/services.dart';

import '../domain/places/town_search.dart';

Future<TownIndex>? _towns;

Future<TownIndex> loadTowns() => _towns ??= () async {
      final data = await rootBundle.load('assets/sky/towns.json.gz');
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      return Isolate.run(() => decodeTowns(bytes));
    }()
        .catchError((Object e) {
      _towns = null; // try again next time
      throw e;
    });

TownIndex decodeTowns(List<int> gz) =>
    TownIndex.fromRows(jsonDecode(utf8.decode(gzip.decode(gz))) as List<Object?>);
