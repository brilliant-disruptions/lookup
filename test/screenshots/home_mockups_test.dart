// Four directions for the Tonight (home) tab, as mockups built from the
// app's own theme and kit so they read like the product. Not wired to data:
// every screen shows the same night (Nashville; ISS at 10:17 PM; clear until
// 2 AM; aurora possible after midnight; Saturn up; Moon sets 11:40 PM).
//   flutter test --update-goldens --tags screenshots --run-skipped test/screenshots/home_mockups_test.dart
@Tags(['screenshots'])
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/ui/kit/kit.dart';
import 'package:lookup/ui/theme.dart';

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.view(File(f).readAsBytesSync().buffer)));
    }
    await loader.load();
  }

  const cache = '/opt/flutter/bin/cache/artifacts/material_fonts';
  await load('MaterialIcons', ['$cache/MaterialIcons-Regular.otf']);
  await load('Inter', ['assets/fonts/InterVariable.ttf']);
}

// ── Shared chrome ────────────────────────────────────────────────────────

Widget _phone(Widget body, {int tab = 0, bool sky = true, bool extendBody = true}) => MaterialApp(
  theme: buildLookUpTheme(),
  debugShowCheckedModeBanner: false,
  home: Scaffold(
    extendBodyBehindAppBar: true,
    extendBody: extendBody,
    appBar: AppHeader(
      title: Text.rich(
        TextSpan(
          text: 'LookUp',
          children: [
            TextSpan(
              text: '.',
              style: TextStyle(color: LookUpColors.blue),
            ),
          ],
        ),
      ),
      place: 'Nashville',
      onPlaceTap: () {},
      actions: [
        CircleButton(icon: Icons.remove_red_eye_rounded, color: LookUpColors.red, onPressed: () {}),
        CircleButton(icon: Icons.settings_outlined, onPressed: () {}),
      ],
    ),
    body: body,
    bottomNavigationBar: FloatingTabBar(
      index: tab,
      onSelect: (_) {},
      tabs: [
        const TabItem(Icons.nightlight_outlined, 'Tonight', activeIcon: Icons.nightlight_round),
        if (sky) const TabItem(Icons.explore_outlined, 'Sky', activeIcon: Icons.explore_rounded),
        const TabItem(Icons.view_agenda_outlined, 'Week', activeIcon: Icons.view_agenda_rounded),
        const TabItem(Icons.auto_awesome_outlined, 'Log', activeIcon: Icons.auto_awesome_rounded),
      ],
    ),
  ),
);

double _top(BuildContext c) => MediaQuery.paddingOf(c).top + AppHeader.height;

/// Fraction of the night (6 PM → 6 AM) for a clock time like 22.28 (10:17 PM).
double _f(double hour) => ((hour < 12 ? hour + 24 : hour) - 18) / 12;

Widget _row(SkyEventType? type, String title, String sub, {Widget? trailing, IconData? icon, Color? color}) => Padding(
  padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
  child: Row(
    children: [
      icon != null ? EventGlyph(icon: icon, color: color!) : EventGlyph.forType(type),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(sub, style: const TextStyle(fontSize: 13.5, color: LookUpColors.grey)),
          ],
        ),
      ),
      ?trailing,
    ],
  ),
);

/// Dusk-to-dawn strip: dark hours, cloud after 2 AM, the Moon until it sets,
/// and tonight's things as ticks with labels.
class _NightStrip extends StatelessWidget {
  const _NightStrip({this.height = 64});
  final double height;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: height + 22,
    child: CustomPaint(painter: _NightStripPainter(height), size: Size.infinite),
  );
}

class _NightStripPainter extends CustomPainter {
  _NightStripPainter(this.h);
  final double h;
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final bar = RRect.fromRectAndRadius(Rect.fromLTWH(0, h - 18, w, 14), const Radius.circular(7));
    // Twilight → dark → twilight.
    canvas.drawRRect(
      bar,
      Paint()
        ..shader = LinearGradient(
          colors: const [Color(0xFF3A3F5C), Color(0xFF16204A), Color(0xFF16204A), Color(0xFF3A3F5C)],
          stops: [0, _f(19.3), _f(5.6), 1],
        ).createShader(bar.outerRect),
    );
    // Clouds after 2 AM.
    final cloud = Rect.fromLTRB(_f(2) * w, h - 18, w, h - 4);
    canvas.save();
    canvas.clipRRect(bar);
    canvas.drawRect(cloud, Paint()..color = const Color(0xCC6B7385));
    canvas.restore();
    // The Moon until 11:40 PM.
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(0, h - 26, _f(23.66) * w, h - 22), const Radius.circular(2)),
      Paint()..color = const Color(0x99F4F6FA),
    );
    void tick(double hour, Color c, String label, {double lift = 0, bool leftOf = false}) {
      final x = _f(hour) * w;
      canvas.drawLine(
        Offset(x, h - 22 - lift),
        Offset(x, h),
        Paint()
          ..color = c
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(Offset(x, h - 26 - lift), 5, Paint()..color = c);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(fontFamily: 'Inter', fontSize: 11.5, fontWeight: FontWeight.w600, color: c),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final lx = leftOf ? x - tp.width - 8 : x - tp.width / 2;
      tp.paint(canvas, Offset(lx.clamp(0, w - tp.width), h - 44 - lift - tp.height / 2));
    }

    tick(21.66, LookUpColors.gold, 'Saturn', leftOf: true);
    tick(22.28, LookUpColors.blue, 'ISS 10:17', lift: 10);
    tick(0.5, LookUpColors.good, 'Aurora?', lift: 0);
    for (final (hour, label) in [(18.0, '6 PM'), (22.0, '10'), (2.0, '2 AM'), (6.0, '6')]) {
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: LookUpColors.greyDim),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = _f(hour) * w;
      tp.paint(canvas, Offset((x - tp.width / 2).clamp(0, w - tp.width), h + 4));
    }
  }

  @override
  bool shouldRepaint(_NightStripPainter old) => false;
}

// ── A. The verdict ───────────────────────────────────────────────────────

class _Verdict extends StatelessWidget {
  const _Verdict();
  @override
  Widget build(BuildContext context) => SkyBackdrop(
    stars: false,
    glow: LookUpColors.good,
    child: Stack(
      children: [
        const Positioned.fill(child: Starfield(density: 0.0004, maxOpacity: 0.6)),
        ListView(
          padding: EdgeInsets.fromLTRB(20, _top(context) + 18, 20, 120),
          children: [
            const Kicker('Tonight', color: LookUpColors.good, live: true),
            const SizedBox(height: 8),
            Text('Go out\nat 10:17.', style: display(52, weight: FontWeight.w800, height: 1.0)),
            const SizedBox(height: 12),
            const Text(
              'The space station, brighter than any star. Face west-southwest; it climbs high in the sky.',
              style: TextStyle(fontSize: 16.5, color: LookUpColors.grey, height: 1.4),
            ),
            const SizedBox(height: 16),
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Pill('Clear till 2 AM', icon: Icons.nightlight_round, color: LookUpColors.good),
                Pill('Moon sets 11:40', icon: Icons.dark_mode_rounded),
                Pill('Saturn up', dot: true, color: LookUpColors.gold),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.explore_rounded), label: const Text('Where to look')),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('in', style: TextStyle(fontSize: 12, color: LookUpColors.grey)),
                    Text('3h 12m', style: numeric(size: 20, weight: FontWeight.w700)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 26),
            const _NightStrip(),
            const SizedBox(height: 18),
            GroupedList(
              indent: 64,
              children: [
                _row(SkyEventType.auroraOutlook, 'Aurora possible', 'After midnight, look north', trailing: const CloudPill(30)),
                _row(SkyEventType.planetHighlight, 'Saturn', 'Best 9:40 PM, south-east'),
                _row(SkyEventType.starlinkTrain, 'Starlink train', 'Tomorrow night, 10:45 PM', trailing: const CloudPill(45)),
              ],
            ),
          ],
        ),
      ],
    ),
  );
}

// ── B. Tonight's window ──────────────────────────────────────────────────

class _Window extends StatelessWidget {
  const _Window();
  @override
  Widget build(BuildContext context) {
    final top = _top(context);
    return Container(
      color: LookUpColors.black,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          SizedBox(
            height: top + 330,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF050914), Color(0xFF0B1630), Color(0xFF1C2E52)],
                    ),
                  ),
                ),
                const Starfield(density: 0.0009, maxOpacity: 0.85),
                Padding(
                  padding: EdgeInsets.only(top: top),
                  child: const CustomPaint(painter: _WindowPainter()),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: GlassCard(
              tint: LookUpColors.blue,
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Row(
                children: [
                  EventGlyph.forType(SkyEventType.iss, size: 44),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('10:17 PM · in 3h 12m', style: numeric(size: 13.5, color: LookUpColors.grey)),
                        Text('ISS flyover', style: display(22, weight: FontWeight.w700)),
                        const Text('Face west-southwest, high in the sky', style: TextStyle(fontSize: 14, color: LookUpColors.grey)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: LookUpColors.greyDim),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GroupedList(
              indent: 64,
              children: [
                _row(SkyEventType.auroraOutlook, 'Aurora possible', 'After midnight, look north'),
                _row(SkyEventType.planetHighlight, 'Saturn', 'Best 9:40 PM, south-east'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The night as one picture: horizon, a clock along it, and each thing where
/// and when it happens; drag the bright line to scrub.
class _WindowPainter extends CustomPainter {
  const _WindowPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final horizon = h * 0.78;
    // Aurora glow after midnight, on the right.
    final ax0 = _f(23.8) * w, ax1 = _f(3) * w;
    canvas.drawRect(
      Rect.fromLTRB(ax0, horizon - 120, ax1, horizon),
      Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22)
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [LookUpColors.good.withValues(alpha: 0.45), LookUpColors.good.withValues(alpha: 0)],
        ).createShader(Rect.fromLTRB(ax0, horizon - 120, ax1, horizon)),
    );
    // Clouds rolling in after 2 AM.
    final cx = _f(2) * w;
    for (var i = 0; i < 4; i++) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx + 30 + i * 48.0, 40 + (i % 2) * 26.0), width: 150, height: 54),
        Paint()
          ..color = const Color(0x556B7385)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }
    // Saturn, a steady gold point.
    final sat = Offset(_f(20.2) * w, horizon - 190);
    canvas.drawCircle(sat, 12, Paint()..color = LookUpColors.gold.withValues(alpha: 0.25));
    canvas.drawCircle(sat, 4, Paint()..color = LookUpColors.gold);
    // The station's arc at 10:17.
    final x0 = _f(21.5) * w, x1 = _f(23.1) * w;
    final arc = Path()
      ..moveTo(x0 - 40, horizon - 4)
      ..quadraticBezierTo((x0 + x1) / 2, horizon - 300, x1 + 40, horizon - 4);
    canvas.drawPath(
      arc,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = LookUpColors.blue,
    );
    canvas.drawCircle(Offset((x0 + x1) / 2, horizon - 152), 7, Paint()..color = Colors.white);
    canvas.drawCircle(Offset((x0 + x1) / 2, horizon - 152), 20, Paint()..color = LookUpColors.blue.withValues(alpha: 0.3));
    // Moon low in the west, setting 11:40.
    final moon = Offset(_f(23.75) * w, horizon - 14);
    canvas.drawCircle(moon, 9, Paint()..color = const Color(0xFFE9E6DA));
    // Ground.
    canvas.drawRect(Rect.fromLTRB(0, horizon, w, h), Paint()..color = const Color(0xFF070B16));
    canvas.drawLine(Offset(0, horizon), Offset(w, horizon), Paint()..color = LookUpColors.blue.withValues(alpha: 0.25));
    // Clock along the horizon.
    for (var hour = 18; hour <= 30; hour += 2) {
      final x = (hour - 18) / 12 * w;
      final label = hour % 24 == 0
          ? '12'
          : '${(hour % 12 == 0) ? 12 : hour % 12}${hour == 18
                ? ' PM'
                : hour == 30
                ? ' AM'
                : ''}';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(fontFamily: 'Inter', fontSize: 11.5, color: LookUpColors.grey),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((x - tp.width / 2).clamp(4, w - tp.width - 4), horizon + 12));
    }
    // The scrubber, parked on the next thing.
    final sx = _f(22.28) * w;
    canvas.drawLine(
      Offset(sx, 18),
      Offset(sx, horizon + 6),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..strokeWidth = 1.5,
    );
    final tp = TextPainter(
      text: const TextSpan(
        text: 'Clear till 2 AM',
        style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: LookUpColors.good),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(18, 14));
  }

  @override
  bool shouldRepaint(_WindowPainter old) => false;
}

// ── C. Home is the sky ───────────────────────────────────────────────────

class _SkyHome extends StatelessWidget {
  const _SkyHome();
  @override
  Widget build(BuildContext context) {
    final top = _top(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF03060E), Color(0xFF0A1630), Color(0xFF1B2D52)],
              stops: [0, 0.55, 0.78],
            ),
          ),
        ),
        const Starfield(density: 0.0012, maxOpacity: 0.95),
        const CustomPaint(painter: _PanoramaPainter()),
        Positioned(
          top: top + 14,
          left: 16,
          right: 16,
          child: GlassCard(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                EventGlyph.forType(SkyEventType.iss),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('ISS flyover · 10:17 PM', style: TextStyle(fontSize: 13, color: LookUpColors.grey)),
                      Text('Rises right there', style: display(19, weight: FontWeight.w700)),
                    ],
                  ),
                ),
                Text('3h 12m', style: numeric(size: 22, weight: FontWeight.w700)),
              ],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 118),
            decoration: const BoxDecoration(
              color: Color(0xF010141D),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(top: BorderSide(color: LookUpColors.line)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(color: LookUpColors.greyDim, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Tonight · clear till 2 AM', style: display(18, weight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Wrap(
                  spacing: 8,
                  children: [
                    Pill('Aurora possible', dot: true, color: LookUpColors.good),
                    Pill('Saturn', dot: true, color: LookUpColors.gold),
                    Pill('Moon 38%', icon: Icons.dark_mode_rounded),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Facing west-southwest: horizon, compass words, the pass drawn on, Saturn.
class _PanoramaPainter extends CustomPainter {
  const _PanoramaPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final horizon = h * 0.72;
    final ground = Path()
      ..moveTo(0, horizon + 6)
      ..quadraticBezierTo(w * 0.3, horizon - 14, w * 0.6, horizon + 2)
      ..quadraticBezierTo(w * 0.85, horizon + 12, w, horizon - 6)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    // The pass: from its rise point near the horizon, up and over.
    final rise = Offset(w * 0.3, horizon - 6);
    final path = Path()
      ..moveTo(rise.dx, rise.dy)
      ..quadraticBezierTo(w * 0.62, horizon - 520, w * 1.15, horizon - 260);
    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = LookUpColors.blue.withValues(alpha: 0.85);
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 18) {
        canvas.drawPath(m.extractPath(d, math.min(d + 10, m.length)), dash);
      }
    }
    canvas.drawCircle(rise, 22, Paint()..color = Colors.white.withValues(alpha: 0.25));
    canvas.drawCircle(rise, 8, Paint()..color = Colors.white);
    void label(String s, Offset at, {double size = 13, Color color = LookUpColors.white, FontWeight weight = FontWeight.w600}) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(fontFamily: 'Inter', fontSize: size, fontWeight: weight, color: color),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, at - Offset(tp.width / 2, 0));
    }

    label('10:17 PM', rise + const Offset(0, -46), size: 15, weight: FontWeight.w700);
    // Saturn.
    final sat = Offset(w * 0.78, horizon - 210);
    canvas.drawCircle(sat, 12, Paint()..color = LookUpColors.gold.withValues(alpha: 0.25));
    canvas.drawCircle(sat, 4.5, Paint()..color = LookUpColors.gold);
    label('Saturn', sat + const Offset(0, 12), color: LookUpColors.gold);
    canvas.drawPath(ground, Paint()..color = const Color(0xFF060A14));
    for (final (s, x) in [('SW', 0.12), ('WSW', 0.3), ('W', 0.5), ('WNW', 0.7), ('NW', 0.9)]) {
      label(s, Offset(w * x, horizon + 18), color: s == 'WSW' ? LookUpColors.white : LookUpColors.greyDim, size: 12.5);
    }
  }

  @override
  bool shouldRepaint(_PanoramaPainter old) => false;
}

// ── D. Nights strip ──────────────────────────────────────────────────────

class _Nights extends StatelessWidget {
  const _Nights();
  @override
  Widget build(BuildContext context) {
    const nights = [
      ('Tonight', 'Fri', LookUpColors.good, [LookUpColors.blue, LookUpColors.good]),
      ('Sat', '1', LookUpColors.warn, [LookUpColors.violet]),
      ('Sun', '2', LookUpColors.greyDim, <Color>[]),
      ('Mon', '3', LookUpColors.good, [LookUpColors.blue]),
      ('Tue', '4', LookUpColors.good, [LookUpColors.gold]),
      ('Wed', '5', LookUpColors.warn, <Color>[]),
    ];
    return SkyBackdrop(
      stars: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(0, _top(context) + 14, 0, 120),
        children: [
          SizedBox(
            height: 92,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final (i, (day, date, quality, things)) in nights.indexed)
                  Container(
                    width: 74,
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: i == 0 ? LookUpColors.blue.withValues(alpha: 0.14) : LookUpColors.glass,
                      borderRadius: BorderRadius.circular(Radii.md),
                      border: Border.all(color: i == 0 ? LookUpColors.blue : LookUpColors.line, width: i == 0 ? 1.5 : 1),
                    ),
                    child: Column(
                      children: [
                        Text(
                          day,
                          style: TextStyle(
                            fontSize: 12,
                            color: i == 0 ? LookUpColors.blue : LookUpColors.grey,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(date, style: numeric(size: 20, weight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(color: quality, shape: BoxShape.circle),
                            ),
                            for (final c in things) ...[
                              const SizedBox(width: 3),
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Kicker('Tonight', color: LookUpColors.good),
                      Text('A great night', style: display(32, weight: FontWeight.w700)),
                      const Text('Clear till 2 AM · Moon sets 11:40', style: TextStyle(fontSize: 14.5, color: LookUpColors.grey)),
                    ],
                  ),
                ),
                const _Score(8),
              ],
            ),
          ),
          const Padding(padding: EdgeInsets.fromLTRB(20, 18, 20, 4), child: _NightStrip(height: 58)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GroupedList(
              indent: 64,
              children: [
                _row(
                  SkyEventType.iss,
                  'ISS flyover',
                  '10:17 PM · face west-southwest',
                  trailing: Text('3h 12m', style: numeric(size: 15, weight: FontWeight.w700)),
                ),
                _row(SkyEventType.planetHighlight, 'Saturn', 'Best 9:40 PM, south-east'),
                _row(SkyEventType.auroraOutlook, 'Aurora possible', 'After midnight, look north'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "8/10" in a ring, the night's score.
class _Score extends StatelessWidget {
  const _Score(this.score);
  final int score;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 66,
    height: 66,
    child: Stack(
      alignment: Alignment.center,
      children: [
        SizedBox.expand(
          child: CircularProgressIndicator(value: score / 10, strokeWidth: 5, color: LookUpColors.good, backgroundColor: LookUpColors.line),
        ),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$score',
                style: numeric(size: 22, weight: FontWeight.w700),
              ),
              TextSpan(
                text: '/10',
                style: numeric(size: 12, color: LookUpColors.grey),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

// ── Render ───────────────────────────────────────────────────────────────

void main() {
  setUpAll(_loadFonts);

  Future<void> shot(WidgetTester t, Widget w, String name) async {
    t.view.physicalSize = const Size(1179, 2556);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(w);
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/home-mockups/$name.png'));
  }

  testWidgets('A verdict', (t) => shot(t, _phone(const _Verdict()), 'a-verdict'));
  testWidgets('B window', (t) => shot(t, _phone(const _Window()), 'b-window'));
  testWidgets('C sky home', (t) => shot(t, _phone(const _SkyHome(), sky: false), 'c-sky-home'));
  testWidgets('D nights', (t) => shot(t, _phone(const _Nights()), 'd-nights'));
}
