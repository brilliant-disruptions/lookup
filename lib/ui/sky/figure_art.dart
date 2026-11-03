/// The constellation artwork for the panorama. The list is small and loaded
/// once; each image is decoded only when its figure first comes into view,
/// and listeners hear when it's ready.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/sky/figures.dart';

class FigureArt extends ChangeNotifier {
  FigureArt(this.figures);

  final List<ConstellationFigure> figures;
  final _images = <String, ui.Image>{};
  final _loading = <String>{};

  static Future<FigureArt>? _shared;

  /// Shared by every panorama; a failed load tries again next time.
  static Future<FigureArt> load() => _shared ??= () async {
        try {
          final json = jsonDecode(await rootBundle.loadString('assets/sky/figures.json')) as Map<String, Object?>;
          return FigureArt(ConstellationFigure.listFromJson(json));
        } catch (_) {
          _shared = null;
          rethrow;
        }
      }();

  /// The decoded image, or null while it's still on its way.
  ui.Image? image(ConstellationFigure f) {
    final img = _images[f.id];
    if (img == null && _loading.add(f.id)) _decode(f);
    return img;
  }

  Future<void> _decode(ConstellationFigure f) async {
    try {
      final bytes = await rootBundle.load('assets/sky/figures/${f.file}');
      // Faint and soft on screen, so 384 px is plenty and keeps memory down.
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List(), targetWidth: min(f.width, 384).round());
      _images[f.id] = (await codec.getNextFrame()).image;
      notifyListeners();
    } catch (_) {
      // No picture for this one; the lines still show.
    }
  }
}
