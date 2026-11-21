/// Pip at the right end of the tab bar, in a slot the size of a tab: the
/// way into the camera from anywhere in the app. Its glow stays inside the
/// slot, so it never spills over the page.
/// It sits there as the character (breathing, glancing, blinking), says hi
/// now and then (a ripple and a droplet), squishes when touched, and a tap
/// opens the live sky through the camera, where it becomes the dot that
/// leads the way. Holding it down just makes it say hi.
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
/// the camera opens and back here when it closes. It's the last slot of
/// [FloatingTabBar]'s capsule: 16 in from the screen's edge plus the
/// capsule's 5 of padding, and the bar's bottom inset is at least 10.
({double x, double y}) pipHomeOffset(Size screen, EdgeInsets padding) => (
      x: screen.width / 2 - 16 - 5 - PipButton.size / 2,
      y: screen.height / 2 - (padding.bottom < 10 ? 10 : padding.bottom) - 5 - PipButton.size / 2,
    );

class PipButton extends StatefulWidget {
  const PipButton({super.key, required this.onTap, this.waveEvery = const Duration(seconds: 40)});

  final VoidCallback onTap;

  /// How often Pip says hi on its own while it's on screen; null never.
  final Duration? waveEvery;

  /// As tall as a tab.
  static const size = 54.0;

  @override
  State<PipButton> createState() => _PipButtonState();
}

class _PipButtonState extends State<PipButton> {
  /// What Pip last did, and a count so doing it again replays it.
  PipState _state = PipState.idle;
  int _replay = 0;

  /// Touches: each one squishes Pip.
  int _pokes = 0;
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
          onTapDown: (_) => setState(() => _pokes++),
          onTap: () {
            HapticFeedback.lightImpact();
            widget.onTap();
          },
          onLongPress: () {
            HapticFeedback.selectionClick();
            _wave();
          },
          child: SizedBox.square(
            dimension: PipButton.size,
            // The glow stays in its slot; the ripple of a hello is cut at
            // the edge, which reads as the slot lighting up.
            child: ClipOval(
              child: ColoredBox(
                color: LookUpColors.good.withValues(alpha: 0.07),
                child: OverflowBox(
                  maxWidth: 96,
                  maxHeight: 96,
                  child: PipMark(
                    size: 52,
                    glow: 0.4,
                    state: _state,
                    replay: _replay,
                    poke: _pokes,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
