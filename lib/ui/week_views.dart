/// The Week tab's two views and the glider between them: every night as
/// one bar from 5 PM to 7 AM ("At a glance"), and two weeks as a calendar.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/models/sky_event.dart';
import '../domain/plan/week_view.dart';
import 'format.dart';
import 'kit/kit.dart';
import 'look_sheet.dart';
import 'plan_screen.dart';
import 'satellites_screen.dart';
import 'paywall_sheet.dart';
import 'theme.dart';
import 'where_to_go_screen.dart';

/// A two-way switch whose thumb glides with the pages under it, so a swipe
/// and a tap feel like the same thing.
class WeekGlider extends StatelessWidget {
  const WeekGlider({super.key, required this.controller, required this.labels, required this.icons});
  final PageController controller;
  final List<String> labels;
  final List<IconData> icons;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final page = controller.hasClients && controller.position.haveDimensions
              ? (controller.page ?? 0.0)
              : controller.initialPage.toDouble();
          final n = labels.length;
          return Container(
            height: 42,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: LookUpColors.line),
            ),
            child: LayoutBuilder(builder: (context, box) {
              final w = box.maxWidth / n;
              return Stack(children: [
                Positioned(
                  left: page.clamp(0.0, n - 1.0) * w,
                  top: 0,
                  bottom: 0,
                  width: w,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: LookUpColors.white,
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 10, offset: Offset(0, 2))],
                    ),
                  ),
                ),
                Row(children: [
                  for (var i = 0; i < n; i++)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: page.round() == i,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (MediaQuery.of(context).disableAnimations) {
                              controller.jumpToPage(i);
                            } else {
                              controller.animateToPage(i, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
                            }
                          },
                          child: Builder(builder: (context) {
                            // Dark on the thumb, grey off it, blending as it glides.
                            final on = (1 - (page - i).abs()).clamp(0.0, 1.0);
                            final c = Color.lerp(LookUpColors.grey, LookUpColors.black, on)!;
                            return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(icons[i], size: 16, color: c),
                              const SizedBox(width: 6),
                              Text(labels[i], style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c)),
                            ]);
                          }),
                        ),
                      ),
                    ),
                ]),
              ]);
            }),
          );
        },
      );
}

/// "Fri" over "30", the selected night in blue.
class _NightLabel extends StatelessWidget {
  const _NightLabel(this.date, {required this.selected});
  final DateTime date;
  final bool selected;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 40,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(DateFormat.E().format(date),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: selected ? LookUpColors.blue : LookUpColors.white)),
          Text('${date.day}', style: numeric(size: 11, color: LookUpColors.greyDim)),
        ]),
      );
}

/// Every night this week as one bar from 5 PM to 7 AM: cloud shaded in, a
/// marker at each sight's time. Tap one for its details below.
class GlancePage extends StatelessWidget {
  const GlancePage({
    super.key,
    required this.nights,
    required this.night,
    required this.pick,
    required this.isPlus,
    required this.onNight,
    required this.onPick,
    required this.bottomPadding,
  });
  final List<WeekNight> nights;
  final DateTime night;
  final SkyEvent? pick;
  final bool isPlus;
  final ValueChanged<DateTime> onNight;
  final ValueChanged<SkyEvent> onPick;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) => ListView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding),
        children: [
          const _Axis(),
          const SizedBox(height: 4),
          for (final n in nights)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                _NightLabel(n.date, selected: n.date == night),
                const SizedBox(width: 8),
                Expanded(child: _NightBar(n, selected: n.date == night, pick: pick, onNight: onNight, onPick: onPick)),
              ]),
            ),
          const SizedBox(height: 4),
          const Wrap(spacing: 14, runSpacing: 4, children: [
            _Key(icon: Icons.dark_mode_outlined, label: 'Dark band is the night'),
            _Key(icon: Icons.texture_rounded, label: 'Cloud'),
            _Key(icon: Icons.circle_outlined, label: 'Faded: no alert'),
          ]),
          const SizedBox(height: 14),
          if (pick case final e?)
            _PickCard(e, locked: lockedOnFree(e, isPlus: isPlus))
          else
            const GlassCard(
              child: Text('Nothing worth stepping out for this week. We\'ll tap you when there is.',
                  style: TextStyle(color: LookUpColors.grey, height: 1.45)),
            ),
          const SizedBox(height: 14),
          const WeekTools(),
        ],
      );
}

/// The hours across the top of the bars.
class _Axis extends StatelessWidget {
  const _Axis();
  @override
  Widget build(BuildContext context) => Row(children: [
        const SizedBox(width: 48),
        Expanded(
          child: SizedBox(
            height: 16,
            child: LayoutBuilder(builder: (context, box) {
              final style = numeric(size: 10.5, color: LookUpColors.greyDim);
              String h(int hour) => DateFormat.j().format(DateTime(2000, 1, 1, hour));
              return Stack(clipBehavior: Clip.none, children: [
                for (final (hour, f) in [(17, 0.0), (21, 4 / 14), (1, 8 / 14), (5, 12 / 14)])
                  // Every four hours; a 7 AM at the end would run into 5 AM.
                  Positioned(left: f * box.maxWidth, child: Text(h(hour), style: style)),
              ]);
            }),
          ),
        ),
      ]);
}

class _Key extends StatelessWidget {
  const _Key({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: LookUpColors.greyDim),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: LookUpColors.greyDim)),
      ]);
}

class _NightBar extends StatelessWidget {
  const _NightBar(this.n, {required this.selected, required this.pick, required this.onNight, required this.onPick});
  final WeekNight n;
  final bool selected;
  final SkyEvent? pick;
  final ValueChanged<DateTime> onNight;
  final ValueChanged<SkyEvent> onPick;

  static const _size = 22.0;

  /// Room between neighbouring markers and at the bar's ends.
  static const _gap = 3.0, _edge = 2.0;

  /// Each marker's left edge, icon centred on its time.
  List<double> _iconLefts(double w) {
    final xs = <double>[];
    for (final e in n.events) {
      var x = barPosition(e.start) * w;
      if (xs.isNotEmpty) x = math.max(x, xs.last + _size * 0.8);
      xs.add(x.clamp(_size / 2 + _edge, w - _size / 2 - _edge));
    }
    return [for (final x in xs) x - _size / 2];
  }

  /// Named markers, each starting at its time; pushed right past the one
  /// before, then back left from the bar's end. Null when they can't all fit.
  ({List<double> lefts, List<double> labelWidths})? _namedLayout(BuildContext context, double w) {
    if (n.events.isEmpty) return null;
    final style = DefaultTextStyle.of(context).style.merge(_Marker.labelStyle);
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.15);
    final labels = [
      for (final e in n.events)
        (TextPainter(
          text: TextSpan(text: eventShortName(e), style: style),
          textDirection: Directionality.of(context),
          textScaler: scaler,
          maxLines: 1,
        )..layout(maxWidth: _Marker.maxLabelWidth))
            .width
            .ceilToDouble()
    ];
    final widths = [for (final l in labels) _Marker.widthFor(l)];
    final lefts = <double>[];
    for (var i = 0; i < n.events.length; i++) {
      var x = math.max(barPosition(n.events[i].start) * w - _size / 2, _edge);
      if (i > 0) x = math.max(x, lefts[i - 1] + widths[i - 1] + _gap);
      lefts.add(x);
    }
    var limit = w - _edge;
    for (var i = n.events.length - 1; i >= 0; i--) {
      lefts[i] = math.min(lefts[i], limit - widths[i]);
      limit = lefts[i] - _gap;
    }
    if (lefts.first < _edge) return null;
    return (lefts: lefts, labelWidths: labels);
  }

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: '${fmtDay(DateTime(n.date.year, n.date.month, n.date.day, 20).toUtc())}: '
            '${n.events.isEmpty ? 'nothing' : '${n.events.length} ${n.events.length == 1 ? 'sight' : 'sights'}'}'
            '${n.cloudy ? ', cloudy' : ''}',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onNight(n.date),
          child: Container(
            height: 32,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: selected ? LookUpColors.blue.withValues(alpha: 0.7) : LookUpColors.line),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LayoutBuilder(builder: (context, box) {
                final w = box.maxWidth;
                // Named where there's room ("ISS", "Tiangong"), else just
                // the icons, nudged apart when they'd overlap.
                final named = _namedLayout(context, w);
                final xs = named?.lefts ?? _iconLefts(w);
                return Stack(children: [
                  Positioned.fill(child: CustomPaint(painter: _BarPainter(n.clouds))),
                  for (var i = 0; i < n.events.length; i++)
                    Positioned(
                      left: xs[i],
                      top: (32 - 2 - _size) / 2,
                      child: _Marker(n.events[i],
                          selected: n.events[i].id == pick?.id,
                          onTap: onPick,
                          labelWidth: named?.labelWidths[i]),
                    ),
                ]);
              }),
            ),
          ),
        ),
      );
}

class _Marker extends StatelessWidget {
  const _Marker(this.e, {required this.selected, required this.onTap, this.labelWidth});
  final SkyEvent e;
  final bool selected;
  final ValueChanged<SkyEvent> onTap;

  /// Set when there's room for the name beside the icon.
  final double? labelWidth;

  static const labelStyle = TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, height: 1.1);
  static const maxLabelWidth = 84.0;
  static double widthFor(double label) => _NightBar._size + label + 7;

  @override
  Widget build(BuildContext context) {
    final s = eventStyle(e.type, details: e.details);
    final ink = selected ? LookUpColors.black : s.color;
    final icon = SizedBox(
      width: _NightBar._size,
      height: _NightBar._size,
      child: s.icon == null
          ? Padding(padding: const EdgeInsets.all(3), child: PlanetMark(color: ink))
          : Icon(s.icon, size: 13, color: ink),
    );
    final label = labelWidth;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: '${eventTitle(e)}, ${fmtDay(e.start)}, ${fmtTime(e.start)}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => onTap(e),
        child: Opacity(
          opacity: e.type.pushes || selected ? 1 : 0.5,
          child: Container(
            width: label == null ? _NightBar._size : widthFor(label),
            height: _NightBar._size,
            decoration: BoxDecoration(
              color: selected ? s.color : s.color.withValues(alpha: 0.24),
              borderRadius: BorderRadius.circular(6),
              border: selected ? Border.all(color: LookUpColors.white, width: 2) : null,
            ),
            child: label == null
                ? icon
                : Row(children: [
                    icon,
                    SizedBox(
                      width: label,
                      child: Text(
                        eventShortName(e),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.15),
                        style: labelStyle.copyWith(color: selected ? LookUpColors.black : LookUpColors.white),
                      ),
                    ),
                  ]),
          ),
        ),
      ),
    );
  }
}

/// Twilight at the ends, dark in the middle, cloud hatched in by the hour.
class _BarPainter extends CustomPainter {
  _BarPainter(this.clouds);
  final List<int?> clouds;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(
        r,
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFF1B2A52), Color(0xFF0D1530), Color(0xFF070B18), Color(0xFF0D1530), Color(0xFF1B2A52)],
            stops: [0, 0.14, 0.5, 0.86, 1],
          ).createShader(r));
    final hw = size.width / clouds.length;
    final stripe = Paint()..strokeWidth = 1.4;
    for (var i = 0; i < clouds.length; i++) {
      final c = clouds[i];
      if (c == null || c < 50) continue;
      final a = ((c - 30) / 60).clamp(0.0, 1.0);
      final cell = Rect.fromLTWH(i * hw, 0, hw + 0.5, size.height);
      canvas.drawRect(cell, Paint()..color = LookUpColors.grey.withValues(alpha: 0.1 * a));
      canvas.save();
      canvas.clipRect(cell);
      stripe.color = LookUpColors.grey.withValues(alpha: 0.3 * a);
      for (var x = cell.left - size.height; x < cell.right; x += 6) {
        canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), stripe);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BarPainter o) => o.clouds != clouds;
}

/// The picked sight, in a few words; tap for the Look sheet.
class _PickCard extends StatelessWidget {
  const _PickCard(this.e, {required this.locked});
  final SkyEvent e;
  final bool locked;
  @override
  Widget build(BuildContext context) => GlassCard(
        tint: eventStyle(e.type, details: e.details).color,
        onTap: () => showLookSheet(context, e),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          EventGlyph.of(e, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(eventTitle(e), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 1),
              Text('${fmtDay(e.start)}, ${fmtTime(e.start)}', style: numeric(size: 12.5, color: LookUpColors.grey)),
              const SizedBox(height: 4),
              Text(eventSubtitle(e), style: const TextStyle(fontSize: 13, color: LookUpColors.grey, height: 1.35)),
              if (locked) ...[
                const SizedBox(height: 6),
                const PlusAlertTag(size: 12),
              ] else if (!e.type.pushes) ...[
                const SizedBox(height: 6),
                const Text('No alert', style: TextStyle(fontSize: 12, color: LookUpColors.greyDim)),
              ],
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: LookUpColors.greyDim),
        ]),
      );
}

/// Plan a night, where to go, satellites: one row of chips.
class WeekTools extends StatelessWidget {
  const WeekTools({super.key});
  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
        _ToolChip(icon: Icons.calendar_month_rounded, label: 'Plan a night', onTap: () => openPlan(context)),
        _ToolChip(icon: Icons.near_me_rounded, label: 'Where to go tonight', onTap: () => openWhereToGo(context)),
        _ToolChip(icon: Icons.satellite_alt_rounded, label: 'Satellites tonight', onTap: () => openSatellitesTonight(context)),
      ]);
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: LookUpColors.line),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 15, color: LookUpColors.violet),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );
}

/// Two weeks as a grid: dots for what's coming, hatched where it's cloudy.
/// Tap a night to see it below.
class CalendarPage extends StatelessWidget {
  const CalendarPage({
    super.key,
    required this.days,
    required this.night,
    required this.isPlus,
    required this.onNight,
    required this.bottomPadding,
  });
  final List<WeekNight> days;
  final DateTime night;
  final bool isPlus;
  final ValueChanged<DateTime> onNight;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final sel = days.where((d) => d.date == night).firstOrNull;
    final today = days.where((d) => !d.past).firstOrNull?.date;
    final month = DateFormat.MMM();
    final span = month.format(days.first.date) == month.format(days.last.date)
        ? DateFormat.yMMMM().format(days.first.date)
        : '${month.format(days.first.date)} – ${month.format(days.last.date)}';
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
          child: Row(children: [
            Text(span, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const Spacer(),
            const Text('Two weeks', style: TextStyle(fontSize: 12, color: LookUpColors.greyDim)),
          ]),
        ),
        Row(children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Center(
                child: Text(DateFormat.E().format(days[i].date).substring(0, 1),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: LookUpColors.greyDim)),
              ),
            ),
        ]),
        const SizedBox(height: 4),
        for (var w = 0; w * 7 < days.length; w++)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(children: [
              for (var i = w * 7; i < math.min(days.length, w * 7 + 7); i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.5),
                    child: _DayCell(days[i], selected: days[i].date == night, today: days[i].date == today, onTap: onNight),
                  ),
                ),
            ]),
          ),
        const SizedBox(height: 6),
        // Only the dots actually on the calendar, each named.
        Wrap(spacing: 12, runSpacing: 4, children: [
          for (final (color, label) in _legend(days)) _Dot(color, label),
          const _Key(icon: Icons.texture_rounded, label: 'Cloudy'),
        ]),
        if (sel != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(fmtDay(DateTime(sel.date.year, sel.date.month, sel.date.day, 20).toUtc()),
                      style: display(19, weight: FontWeight.w600)),
                ),
              ),
              Text(_cloudWords(sel), style: const TextStyle(fontSize: 13, color: LookUpColors.grey)),
            ]),
          ),
          if (sel.events.isEmpty)
            const GlassCard(
              child: Text('Nothing worth stepping out for that night.', style: TextStyle(color: LookUpColors.grey)),
            )
          else
            GroupedList(indent: 60, children: [
              for (final e in sel.alerts)
                ListRow(
                  onTap: () => showLookSheet(context, e),
                  leading: EventGlyph.of(e, size: 30),
                  title: eventTitle(e),
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                    Text(fmtTime(e.start), style: numeric(size: 14, weight: FontWeight.w600)),
                    if (lockedOnFree(e, isPlus: isPlus)) ...[
                      const SizedBox(height: 4),
                      const PlusAlertTag(),
                    ],
                  ]),
                ),
              if (sel.quiet.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                  child: Text('Also: ${sel.quiet.map((e) => '${eventTitle(e)} ${fmtTime(e.start)}').join(' · ')}',
                      style: const TextStyle(fontSize: 12.5, color: LookUpColors.greyDim, height: 1.4)),
                ),
            ]),
        ],
        const SizedBox(height: 16),
        const WeekTools(),
      ],
    );
  }

  /// One key per kind of dot on the calendar, in the order they first show.
  static List<(Color, String)> _legend(List<WeekNight> days) {
    final seen = <String>{};
    return [
      for (final d in days)
        for (final e in d.alerts.take(4))
          if (seen.add(_kind(e.type))) (eventStyle(e.type, details: e.details).color, _kind(e.type)),
    ];
  }

  static String _kind(SkyEventType t) => switch (t) {
        SkyEventType.iss => 'ISS',
        SkyEventType.tiangong => 'Tiangong',
        SkyEventType.starlinkTrain => 'Starlink',
        SkyEventType.auroraNow || SkyEventType.auroraOutlook => 'Aurora',
        SkyEventType.meteorShower => 'Meteors',
        SkyEventType.lunarEclipse || SkyEventType.solarEclipse => 'Eclipses',
        SkyEventType.planetPairing || SkyEventType.planetHighlight => 'Planets',
        SkyEventType.rocketLaunch => 'Launches',
        SkyEventType.issTransit => 'Transits',
        SkyEventType.satellitePass => 'Satellites',
        SkyEventType.skyObject => 'Sky',
        SkyEventType.fullMoonRise => 'Full Moon',
      };

  /// How the night's clouds look, from the forecast; nothing claimed
  /// without one.
  static String _cloudWords(WeekNight n) {
    final known = n.clouds.nonNulls.toList();
    if (known.isEmpty) return 'No forecast yet';
    final mean = known.reduce((a, b) => a + b) / known.length;
    return n.cloudy ? 'Cloudy' : mean <= 30 ? 'Mostly clear' : 'Some cloud';
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.color, this.label);
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: LookUpColors.greyDim)),
      ]);
}

class _DayCell extends StatelessWidget {
  const _DayCell(this.d, {required this.selected, required this.today, required this.onTap});
  final WeekNight d;
  final bool selected, today;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final dots = [for (final e in d.alerts.take(4)) eventStyle(e.type, details: e.details).color];
    return Semantics(
      container: true,
      button: !d.past,
      selected: selected,
      label: '${DateFormat.MMMEd().format(d.date)}: '
          '${d.alerts.isEmpty ? 'nothing' : '${d.alerts.length} to see'}${d.cloudy ? ', cloudy' : ''}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: d.past ? null : () => onTap(d.date),
        child: Opacity(
          opacity: d.past ? 0.35 : 1,
          child: AspectRatio(
            aspectRatio: 1 / 1.1,
            child: Container(
              decoration: BoxDecoration(
                color: selected ? LookUpColors.blue.withValues(alpha: 0.16) : Colors.white.withValues(alpha: 0.045),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: selected ? LookUpColors.blue : Colors.transparent, width: 1.2),
              ),
              child: CustomPaint(
                painter: d.cloudy ? _HatchPainter() : null,
                child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  Text('${d.date.day}',
                      style: numeric(size: 14, weight: FontWeight.w700, color: today ? LookUpColors.blue : LookUpColors.white)),
                  SizedBox(
                    height: 6,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      for (final c in dots)
                        Container(
                          width: 5,
                          height: 5,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                        ),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HatchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = LookUpColors.grey.withValues(alpha: 0.16)
      ..strokeWidth = 1.2;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)));
    for (var x = -size.height; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HatchPainter o) => false;
}
