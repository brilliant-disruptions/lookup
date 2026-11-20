/// Pip beside the tab bar: the way into the camera from anywhere in the app.
/// It sits there as the green light, waves now and then (grows a face and
/// hands, waves, back to a dot), and a tap opens the live sky through the
/// camera. Holding it down just makes it wave.
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../kit/kit.dart';
import '../theme.dart';

class PipButton extends StatefulWidget {
  const PipButton({super.key, required this.onTap, this.waveEvery = const Duration(seconds: 40)});

  final VoidCallback onTap;

  /// How often Pip waves on its own while it's on screen; null never.
  final Duration? waveEvery;

  static const size = 64.0;

  @override
  State<PipButton> createState() => _PipButtonState();
}

class _PipButtonState extends State<PipButton> {
  int _waves = 0;
  Timer? _first, _again;

  @override
  void initState() {
    super.initState();
    // Says hi a moment after it first appears, then now and then.
    _first = Timer(const Duration(milliseconds: 700), _wave);
    final every = widget.waveEvery;
    if (every != null) _again = Timer.periodic(every, (_) => _wave());
  }

  @override
  void dispose() {
    _first?.cancel();
    _again?.cancel();
    super.dispose();
  }

  void _wave() {
    if (mounted) setState(() => _waves++);
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
              state: _waves == 0 ? PipState.idle : PipState.wave,
              replay: _waves,
            ),
          ),
        ),
      );
}
