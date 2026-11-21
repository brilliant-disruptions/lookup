/// "Why only at dusk and dawn?": slide through a day until the station
/// shows up over you. A teaching picture (domain/onboarding/first_look.dart):
/// the Earth, the Sun going round, you on top and the station overhead,
/// drawn high so the window is easy to find.
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../domain/onboarding/first_look.dart';
import '../theme.dart';

class TwilightSlider extends StatefulWidget {
  const TwilightSlider({super.key, required this.onFound});

  /// The first time they find it (the station visible over them).
  final VoidCallback onFound;
  @override
  State<TwilightSlider> createState() => _TwilightSliderState();
}

class _TwilightSliderState extends State<TwilightSlider> {
  double _hour = 12;
  bool _found = false;

  String get _time {
    final h = _hour % 24;
    if (h == 12) return 'noon';
    if (h == 0) return 'midnight';
    final hh = h.floor(), mm = ((h - hh) * 60).round();
    return '${(hh + 11) % 12 + 1}:${mm.toString().padLeft(2, '0')} ${hh < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final sight = stationSight(_hour);
    final words = switch (sight) {
      StationSight.day => 'Daytime: too bright to see it.',
      StationSight.visible => 'Dark here, and it\'s still in sunlight: there it is!',
      StationSight.shadow => 'Dark, but it\'s in Earth\'s shadow: it vanishes.',
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AspectRatio(
        aspectRatio: 2.1,
        child: Semantics(
          label: 'The Earth, the Sun, you, and the station overhead. $words',
          child: DecoratedBox(
            decoration: BoxDecoration(color: const Color(0xFF070C1E), borderRadius: BorderRadius.circular(14), border: Border.all(color: LookUpColors.line)),
            child: ClipRRect(borderRadius: BorderRadius.circular(14), child: CustomPaint(painter: _Diagram(_hour, sight))),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text.rich(TextSpan(text: 'Time where you are: ', children: [TextSpan(text: _time, style: const TextStyle(color: LookUpColors.white, fontWeight: FontWeight.w700))]),
          style: const TextStyle(fontSize: 13, color: LookUpColors.grey)),
      Slider(
        key: const Key('twilight-slider'),
        value: _hour,
        min: 0,
        max: 24,
        divisions: 96,
        activeColor: LookUpColors.gold,
        label: _time,
        semanticFormatterCallback: (_) => _time,
        onChanged: (v) {
          setState(() => _hour = v);
          if (!_found && stationSight(v) == StationSight.visible) {
            _found = true;
            widget.onFound();
          }
        },
      ),
      Text(words,
          key: const Key('twilight-words'),
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: sight == StationSight.visible ? LookUpColors.good : LookUpColors.grey)),
    ]);
  }
}

class _Diagram extends CustomPainter {
  _Diagram(this.hour, this.sight);
  final double hour;
  final StationSight sight;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.64);
    final r = size.height * 0.27, k = 1.25;
    final a = (90 + (hour - 12) * 15) * math.pi / 180;
    final sun = Offset(math.cos(a), -math.sin(a)); // screen y down
    final sunAt = c + sun * (size.height * 0.9);
    canvas.drawCircle(sunAt, 40, Paint()..shader = RadialGradient(colors: [const Color(0x99FFD27A), const Color(0x00FFD27A)]).createShader(Rect.fromCircle(center: sunAt, radius: 40)));
    canvas.drawCircle(sunAt, 11, Paint()..color = const Color(0xFFFFD27A));
    // Earth's shadow, away from the Sun.
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(math.atan2(-sun.dy, -sun.dx));
    canvas.drawRect(Rect.fromLTWH(0, -r, size.width * 2, r * 2), Paint()..color = const Color(0x73000000));
    canvas.restore();
    // The Earth: lit on the Sun's side.
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF0D1D3D));
    final start = math.atan2(sun.dy, sun.dx) - math.pi / 2;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), start, math.pi, true, Paint()..color = const Color(0xFF2F6BD1));
    // You, and the station overhead.
    final you = c - Offset(0, r), sat = c - Offset(0, r * k);
    canvas.drawCircle(you, 4, Paint()..color = LookUpColors.white);
    if (sight != StationSight.shadow) {
      final vis = sight == StationSight.visible;
      canvas.drawCircle(sat, vis ? 16 : 10, Paint()..shader = RadialGradient(colors: [Colors.white.withValues(alpha: vis ? 0.8 : 0.35), Colors.white.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: sat, radius: vis ? 16 : 10)));
    }
    canvas.drawCircle(sat, 4, Paint()..color = sight == StationSight.shadow ? const Color(0xFF3A4255) : Colors.white);
    void label(String s, Offset at) {
      final tp = TextPainter(text: TextSpan(text: s, style: display(11, weight: FontWeight.w500, color: LookUpColors.grey)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, at);
    }

    label('you', you + const Offset(8, -2));
    label('station', sat + const Offset(8, -8));
    label('not to scale', Offset(8, size.height - 18));
  }

  @override
  bool shouldRepaint(_Diagram o) => o.hour != hour;
}
