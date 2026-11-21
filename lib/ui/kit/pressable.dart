/// Something you press that answers your finger: it sinks a little while
/// held, springs back on release, and gives a light tick. Used for the Look
/// sheet's guide card and action tiles, so they feel like things, not text.
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.onDown, this.semanticLabel, this.pressedScale = 0.96});

  final Widget child;
  final VoidCallback? onTap;

  /// The moment the finger lands (before [onTap]), e.g. to poke Pip.
  final VoidCallback? onDown;
  final String? semanticLabel;
  final double pressedScale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final on = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: on,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: on
            ? (_) {
                _set(true);
                widget.onDown?.call();
              }
            : null,
        onTapUp: on ? (_) => _set(false) : null,
        onTapCancel: () => _set(false),
        onTap: on
            ? () {
                HapticFeedback.selectionClick();
                widget.onTap!();
              }
            : null,
        child: AnimatedScale(
          scale: _down && !still ? widget.pressedScale : 1,
          duration: Duration(milliseconds: _down ? 90 : 260),
          curve: _down ? Curves.easeOut : Curves.elasticOut,
          child: AnimatedOpacity(
            opacity: _down ? 0.85 : 1,
            duration: const Duration(milliseconds: 120),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
