/// The fixed sky bundled with the app (d3-celestial J2000 data).
library;

import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/sky/catalog.dart';

/// Stars and constellations from the bundled assets (~80 KB).
Future<SkyCatalog> loadBundledCatalog() async {
  final stars = jsonDecode(await rootBundle.loadString('assets/sky/stars.json')) as Map<String, Object?>;
  final cons = jsonDecode(await rootBundle.loadString('assets/sky/constellations.json')) as Map<String, Object?>;
  return SkyCatalog.fromJson(stars, cons);
}
