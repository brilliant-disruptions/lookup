import 'package:flutter/material.dart';

/// Dearly's calm entrance: a transform-only rise (12 px → 0, 520 ms,
/// ease-out), staggered by [delay]. Transform-only means content is always
/// readable even if the animation never runs.
class Rise extends StatefulWidget {
  const Rise({super.key, required this.child, this.delay = Duration.zero, this.index});
  final Widget child;
  final Duration delay;

  /// Convenience: stagger by index × 70 ms.
  final int? index;

  @override
  State<Rise> createState() => _RiseState();
}

class _RiseState extends State<Rise> with SingleTickerProviderStateMixin {
  static const _easeOut = Cubic(0.16, 0.84, 0.44, 1);
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  late final Animation<Offset> _o =
      Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(CurvedAnimation(parent: _c, curve: _easeOut));
  late final Animation<double> _a = Tween(begin: 0.55, end: 1.0).animate(CurvedAnimation(parent: _c, curve: Curves.easeOut));

  @override
  void initState() {
    super.initState();
    final delay = widget.delay + Duration(milliseconds: 70 * (widget.index ?? 0));
    Future.delayed(delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SlideTransition(position: _o, child: FadeTransition(opacity: _a, child: widget.child));
}
