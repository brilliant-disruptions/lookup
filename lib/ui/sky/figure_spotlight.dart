/// Constellation pictures over a camera view, and the one in the middle
/// lighting up as the phone settles on it: shared by the sky camera and the
/// sky finder so both behave the same.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'constellation_glow.dart' show figureFade;
import 'figure_art.dart';

mixin FigureSpotlight<T extends StatefulWidget> on State<T>, TickerProvider {
  /// The pictures, once loaded; null until then.
  FigureArt? figureArt;

  /// The picture in the middle lights up and the last one lets go, as on
  /// the Sky tab: how lit each is, 0 to 1.
  final figureGlow = ValueNotifier<Map<String, double>>(const {});
  late final _glowTicker = createTicker(_stepGlow);
  Duration _glowLast = Duration.zero;
  String? _spotlit;
  String? _ticked;

  /// False under reduced motion: pictures switch instead of fading, and
  /// nothing twinkles. Set on every build.
  bool figureFadeOn = true;

  /// A light tick as a new constellation settles in the middle.
  bool get figureTicks => true;

  /// A running clock (seconds) for the lit constellation's stars to twinkle
  /// by. It only ticks while something is lit and motion is allowed.
  final figureTwinkle = ValueNotifier<double>(0);

  /// Called from paint, so it only starts the ticker; the levels change on
  /// the next frame.
  void onFigureSpotlit(String? id) {
    if (id == _spotlit) return;
    _spotlit = id;
    // Not again for the same one, so wavering on its edge doesn't buzz.
    if (figureTicks && id != null && id != _ticked) {
      _ticked = id;
      HapticFeedback.selectionClick();
    }
    if (!_glowTicker.isActive) {
      _glowLast = Duration.zero;
      _glowTicker.start();
    }
  }

  void _stepGlow(Duration elapsed) {
    final dt = elapsed - _glowLast;
    final step = figureFadeOn ? dt.inMicroseconds / figureFade.inMicroseconds : 1.0;
    _glowLast = elapsed;
    final next = <String, double>{};
    var settled = true, changed = false;
    for (final id in {...figureGlow.value.keys, ?_spotlit}) {
      final target = id == _spotlit ? 1.0 : 0.0;
      final n = ((figureGlow.value[id] ?? 0.0) + (target > 0 ? step : -step)).clamp(0.0, 1.0);
      if (n > 0) next[id] = n;
      if (n != target) settled = false;
      if (n != figureGlow.value[id]) changed = true;
    }
    if (changed) figureGlow.value = next;
    final twinkling = figureFadeOn && _spotlit != null;
    if (twinkling) figureTwinkle.value += dt.inMicroseconds / 1e6;
    if (settled && !twinkling) _glowTicker.stop();
  }

  @override
  void initState() {
    super.initState();
    FigureArt.load().then((art) {
      if (!mounted) return;
      setState(() => figureArt = art..addListener(_onArt));
    }, onError: (_) {});
  }

  void _onArt() => setState(() {});

  @override
  void dispose() {
    figureArt?.removeListener(_onArt);
    _glowTicker.dispose();
    figureGlow.dispose();
    figureTwinkle.dispose();
    super.dispose();
  }
}
