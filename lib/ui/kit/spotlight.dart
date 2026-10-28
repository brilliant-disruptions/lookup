import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';

/// One stop on a spotlight tour: the widget to light up and what to say.
class SpotlightStep {
  const SpotlightStep({required this.target, required this.title, required this.body, this.radius = 22});

  /// Put this key on the widget to light up. A step whose target isn't on
  /// screen is left out.
  final GlobalKey target;
  final String title;
  final String body;
  final double radius;
}

/// Dims the screen and lights up one thing at a time with a caption. Tap
/// anywhere (or Next) to go on; Skip or back ends it. Resolves to true if
/// they saw every stop.
Future<bool> showSpotlight(BuildContext context, List<SpotlightStep> steps) async {
  final shown = steps.where((s) => _rectOf(s.target) != null).toList();
  if (shown.isEmpty) return true;
  final done = await Navigator.of(context).push<bool>(
    PageRouteBuilder(
      opaque: false,
      barrierLabel: 'Tour',
      transitionDuration: const Duration(milliseconds: 250),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) => _Spotlight(shown),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ),
  );
  return done ?? false;
}

Rect? _rectOf(GlobalKey k) {
  final box = k.currentContext?.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

class _Spotlight extends StatefulWidget {
  const _Spotlight(this.steps);
  final List<SpotlightStep> steps;
  @override
  State<_Spotlight> createState() => _SpotlightState();
}

class _SpotlightState extends State<_Spotlight> {
  int _i = 0;
  Rect? _seen;

  // Targets can still be moving (an entrance animation, a scroll): follow them.
  late final Timer _follow = Timer.periodic(const Duration(milliseconds: 200), (_) {
    final r = _rectOf(widget.steps[_i].target);
    if (mounted && r != _seen) setState(() {});
  });

  @override
  void initState() {
    super.initState();
    _follow;
  }

  @override
  void dispose() {
    _follow.cancel();
    super.dispose();
  }

  void _next() {
    if (_i == widget.steps.length - 1) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _i++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_i];
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    _seen = _rectOf(step.target);
    final hole = (_seen ?? Rect.fromCenter(center: size.center(Offset.zero), width: 0, height: 0)).inflate(6);
    final still = MediaQuery.disableAnimationsOf(context);
    final last = _i == widget.steps.length - 1;
    final card = _Caption(
      count: '${_i + 1} of ${widget.steps.length}',
      title: step.title,
      body: step.body,
      last: last,
      onNext: _next,
      onSkip: () => Navigator.of(context).pop(false),
    );
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _next,
              child: ExcludeSemantics(
                child: TweenAnimationBuilder<Rect?>(
                  tween: RectTween(end: hole),
                  duration: still ? Duration.zero : const Duration(milliseconds: 380),
                  curve: Curves.easeOutCubic,
                  builder: (_, r, _) => CustomPaint(painter: _Dim(r ?? hole, step.radius)),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: CustomSingleChildLayout(
              delegate: _CaptionPlace(hole, pad),
              child: AnimatedSwitcher(
                duration: still ? Duration.zero : const Duration(milliseconds: 220),
                child: KeyedSubtree(key: ValueKey(_i), child: card),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Puts the caption just below the lit-up thing if it fits, else just above,
/// else at the bottom of the screen (over a tall card's lower half).
class _CaptionPlace extends SingleChildLayoutDelegate {
  _CaptionPlace(this.hole, this.pad);
  final Rect hole;
  final EdgeInsets pad;
  static const gap = 14.0, side = 16.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) => BoxConstraints(
      maxWidth: c.maxWidth - 2 * side, minWidth: c.maxWidth - 2 * side, maxHeight: c.maxHeight - pad.vertical - 16);

  @override
  Offset getPositionForChild(Size size, Size child) {
    final top = pad.top + 8, bottom = size.height - pad.bottom - 8;
    final below = hole.bottom + gap, above = hole.top - gap - child.height;
    final y = below + child.height <= bottom
        ? below
        : above >= top
            ? above
            : bottom - child.height;
    return Offset(side, y);
  }

  @override
  bool shouldRelayout(_CaptionPlace old) => old.hole != hole || old.pad != pad;
}

class _Caption extends StatelessWidget {
  const _Caption({
    required this.count,
    required this.title,
    required this.body,
    required this.last,
    required this.onNext,
    required this.onSkip,
  });
  final String count, title, body;
  final bool last;
  final VoidCallback onNext, onSkip;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
      decoration: BoxDecoration(
        color: LookUpColors.panelRaised,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: LookUpColors.line),
        boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 30, offset: Offset(0, 12))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            count,
            style: numeric(size: 12.5, color: LookUpColors.blue, weight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(title, style: display(21, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(body, style: const TextStyle(color: LookUpColors.grey, fontSize: 15, height: 1.45)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (!last) TextButton(onPressed: onSkip, child: const Text('Skip')),
              const Spacer(),
              FilledButton(onPressed: onNext, child: Text(last ? 'Got it' : 'Next')),
            ],
          ),
        ],
      ),
    ),
  );
}

class _Dim extends CustomPainter {
  _Dim(this.hole, this.radius);
  final Rect hole;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(hole, Radius.circular(radius));
    final shade = Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(r));
    canvas.drawPath(shade, Paint()..color = const Color(0xC7000000));
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = LookUpColors.blue.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_Dim old) => old.hole != hole || old.radius != radius;
}
