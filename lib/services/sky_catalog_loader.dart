import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/orbit/omm.dart';
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

/// The ISS as it was when this build was made, for a first look when
/// Celestrak can't be reached. Refresh `assets/sky/iss_seed.json` from
/// Celestrak (CATNR=25544, FORMAT=json) before each release: it is only
/// used while under [RefreshService.seedMaxAge] old.
Future<List<OmmRecord>> loadIssSeed() async =>
    OmmRecord.listFromJson(jsonDecode(await rootBundle.loadString('assets/sky/iss_seed.json')));
