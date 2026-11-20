/// Pip beside the tab bar: the way into the camera from anywhere in the app.
/// It sits there as the green light, says hi now and then (a ripple, two
/// eyes, a droplet, back to the dot), and a tap opens the live sky through
/// the camera. Holding it down just makes it say hi.
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../kit/kit.dart';
import '../theme.dart';

/// Told each time Pip comes back home from the camera, so the button's Pip
/// lands (a flare and a little hop) where the flying Pip just arrived.
final pipCameHome = ValueNotifier<int>(0);

/// Where the button's centre is on a [screen]-sized view with [padding], as
/// an offset from the centre (x right, y down): Pip flies out from here when
/// the camera opens and back here when it closes. It sits 16 in from the
/// right, on the tab bar's row ([FloatingTabBar]'s bottom inset is at least
/// 10).
({double x, double y}) pipHomeOffset(Size screen, EdgeInsets padding) => (
      x: screen.width / 2 - 16 - PipButton.size / 2,
      y: screen.height / 2 - (padding.bottom < 10 ? 10 : padding.bottom) - PipButton.size / 2,
    );

class PipButton extends StatefulWidget {
  const PipButton({super.key, required this.onTap, this.waveEvery = const Duration(seconds: 40)});

  final VoidCallback onTap;

  /// How often Pip says hi on its own while it's on screen; null never.
  final Duration? waveEvery;

  static const size = 64.0;

  @override
  State<PipButton> createState() => _PipButtonState();
}

class _PipButtonState extends State<PipButton> {
  /// What Pip last did, and a count so doing it again replays it.
  PipState _state = PipState.idle;
  int _replay = 0;
  Timer? _first, _again;

  @override
  void initState() {
    super.initState();
    // Says hi a moment after it first appears, then now and then.
    _first = Timer(const Duration(milliseconds: 700), _wave);
    final every = widget.waveEvery;
    if (every != null) _again = Timer.periodic(every, (_) => _wave());
    pipCameHome.addListener(_land);
  }

  @override
  void dispose() {
    pipCameHome.removeListener(_land);
    _first?.cancel();
    _again?.cancel();
    super.dispose();
  }

  void _wave() => _play(PipState.greet);

  /// Back from the camera: a flare and a hop, home again.
  void _land() => _play(PipState.found);

  void _play(PipState s) {
    if (mounted) {
      setState(() {
        _state = s;
        _replay++;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Pip. Look at the sky through your camera',
        excludeSemantics: true,
        child: GestureDetector(
          key: const Key('pip-button'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.lightImpact();
            widget.onTap();
          },
          onLongPress: () {
            HapticFeedback.selectionClick();
            _wave();
          },
          child: Container(
            width: PipButton.size,
            height: PipButton.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: LookUpColors.panelRaised.withValues(alpha: 0.96),
              border: Border.all(color: LookUpColors.line),
              boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 30, offset: Offset(0, 10))],
            ),
            alignment: Alignment.center,
            child: PipMark(
              size: 60,
              state: _state,
              replay: _replay,
            ),
          ),
        ),
      );
}
