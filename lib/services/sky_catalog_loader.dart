import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/sky/catalog.dart';

Future<SkyCatalog>? _loading;

/// The bundled stars, constellation figures and proper motions, loaded once
/// and shared by the Sky tab and the refresh (which names landmarks).
Future<SkyCatalog> loadSkyCatalog() => _loading ??= () async {
      try {
        Future<Map<String, Object?>> read(String f) async =>
            jsonDecode(await rootBundle.loadString('assets/sky/$f')) as Map<String, Object?>;
        return SkyCatalog.fromJson(await read('stars.json'), await read('constellations.json'), await read('proper_motion.json'));
      } catch (_) {
        _loading = null; // try again next time
        rethrow;
      }
    }();
