/// Every day as one bar, midnight to midnight ("At a glance"): last week on
/// one tab, today and the days ahead on the other. Hours with nothing on
/// anywhere are chopped out (`DayAxis`), leaving a zig-zag break, and the
/// rest fits the width: the whole week is in view at once, with no swiping
/// sideways. Each sight sits on its real time (`layoutBar`); one that would
/// overlap a neighbour drops a row, and only that day's bar grows.
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../domain/models/sky_event.dart';
import '../domain/plan/bar_layout.dart';
import '../domain/plan/day_axis.dart';
import '../domain/plan/week_view.dart';
import 'format.dart';
import 'kit/kit.dart';
import 'look_sheet.dart';
import 'plan_screen.dart';
import 'satellites_screen.dart';
import 'paywall_sheet.dart';
import 'theme.dart';
import 'where_to_go_screen.dart';

/// "Fri 30" on one line (it never wraps, even with large text), the
/// selected day in blue.
class _NightLabel extends StatelessWidget {
  const _NightLabel(this.date, {required this.selected, this.past = false});
  final DateTime date;
  final bool selected, past;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: _labelWidth,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(TextSpan(children: [
            TextSpan(
                text: DateFormat.E().format(date),
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? LookUpColors.blue : (past ? LookUpColors.grey : LookUpColors.white))),
            TextSpan(text: ' ${date.day}', style: numeric(size: 12.5, color: LookUpColors.greyDim)),
          ])),
        ),
      );
}

/// The day column, and the gap between it and the bars.
const _labelWidth = 48.0, _labelGap = 10.0;

/// Each day's bar, and the room between one day and the next: slim, so the
/// whole week fits on a small phone.
const _barHeight = 32.0, _rowGap = 8.0;
const _barDark = Color(0xFF0D1530);

/// A chopped stretch of hours: wide enough to read as a break.
const _breakPx = 12.0;

/// The pixels one shown hour takes, so the shown hours and the breaks fill
/// a bar [view] wide exactly: the whole day, no swiping.
double _perHour(DayAxis axis, double view) =>
    math.max(1.0, (view - axis.breakCount * _breakPx) / math.max(1, axis.keptHours));

/// Every day as one bar, its hours with something on fitted to the width:
/// cloud shaded in, a marker at each sight's time. "Today and ahead" opens;
/// "Last week" (faded, what went over) is the other tab. Tap one for its
/// details at the bottom.
class GlancePage extends StatefulWidget {
  const GlancePage({
    super.key,
    required this.nights,
    required this.night,
    required this.pick,
    required this.isPlus,
    required this.onNight,
    required this.onPick,
    required this.bottomPadding,
    this.missed,
  });
  final List<WeekNight> nights;
  final DateTime night;
  final SkyEvent? pick;
  final bool isPlus;
  final ValueChanged<DateTime> onNight;
  final ValueChanged<SkyEvent> onPick;
  final double bottomPadding;

  /// Shown at the top of last week when it's worth saying (free users who
  /// missed something clear that LookUp+ would have tapped them for).
  final Widget? missed;

  @override
  State<GlancePage> createState() => _GlancePageState();
}

class _GlancePageState extends State<GlancePage> {
  final _scroll = ScrollController();

  /// Opens on "Today and ahead"; "Last week" is the other tab.
  bool _showPast = false;

  /// One set of hours for every day, so the rows stay lined up on the clock.
  DayAxis get _axis => DayAxis.forStarts([
        for (final n in widget.nights)
          for (final e in n.events) e.start,
      ]);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Widget _row(WeekNight n, DayAxis axis) => Padding(
        padding: const EdgeInsets.only(bottom: _rowGap),
        child: Opacity(
          opacity: n.past ? 0.6 : 1,
          child: Row(children: [
            _NightLabel(n.date, selected: n.date == widget.night, past: n.past),
            const SizedBox(width: _labelGap),
            Expanded(
                child: _NightBar(n,
                    axis: axis,
                    selected: n.date == widget.night,
                    pick: widget.pick,
                    onNight: widget.onNight,
                    onPick: widget.onPick)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final past = widget.nights.where((n) => n.past).toList();
    final ahead = widget.nights.where((n) => !n.past).toList();
    final pick = widget.pick;
    final axis = _axis;
    // The hours sit right above each run of bars and scroll with them, so
    // they never float over something else (last week's card, say).
    return Column(children: [
      Expanded(
        child: SingleChildScrollView(
          key: const Key('week-list'),
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (past.isNotEmpty)
              _Tabs(showPast: _showPast, onChanged: (v) => setState(() => _showPast = v)),
            if (_showPast && past.isNotEmpty) ...[
              if (widget.missed case final m?) Padding(padding: const EdgeInsets.only(bottom: 14), child: m),
              _Axis(axis),
              for (final n in past) _row(n, axis),
            ] else ...[
              if (past.isEmpty) const _Section('Today and ahead'),
              _Axis(axis),
              for (final n in ahead) _row(n, axis),
            ],
            const SizedBox(height: 6),
            const Wrap(spacing: 14, runSpacing: 6, children: [
              _Key(icon: Icons.more_vert_rounded, label: 'Zig-zag: hours with nothing on'),
              _Key(icon: Icons.texture_rounded, label: 'Cloud'),
              _Key(icon: Icons.circle_outlined, label: 'Faded: no alert'),
            ]),
            const SizedBox(height: 18),
            const WeekTools(),
          ]),
        ),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, widget.bottomPadding),
        child: pick != null
            ? _PickCard(pick, locked: lockedOnFree(pick, isPlus: widget.isPlus))
            : const GlassCard(
                child: Text('Nothing worth stepping out for yet. We\'ll tap you when there is.',
                    style: TextStyle(color: LookUpColors.grey, height: 1.45)),
              ),
      ),
    ]);
  }
}

/// "Last week" | "Today and ahead": which half of the list is showing.
class _Tabs extends StatelessWidget {
  const _Tabs({required this.showPast, required this.onChanged});
  final bool showPast;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    Widget tab(String label, bool past) {
      final on = showPast == past;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(past),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(
                color: on ? LookUpColors.blue.withValues(alpha: 0.18) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: on ? LookUpColors.blue : LookUpColors.grey)),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: Row(children: [tab('Last week', true), const SizedBox(width: 6), tab('Today and ahead', false)]),
    );
  }
}

/// A heading when there's no tab to choose.
class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 12),
        child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: LookUpColors.grey)),
      );
}

/// The hours across the top of the bars: as many as fit without crowding.
/// Each stretch starts with its hour in full ("10 PM"); the rest are just
/// the number ("11", "12"), and a dotted mark sits where hours were cut.
class _Axis extends StatelessWidget {
  const _Axis(this.axis);
  final DayAxis axis;

  /// Labels no closer than this, so they never run together.
  static const _minGap = 6.0;

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        const SizedBox(width: _labelWidth + _labelGap),
        Expanded(
          child: SizedBox(
            height: 16,
            child: LayoutBuilder(builder: (context, box) {
              final view = box.maxWidth - 2;
              final perHour = _perHour(axis, view);
              final style = numeric(size: 10.5, color: LookUpColors.greyDim);
              final scaler = MediaQuery.textScalerOf(context);
              double widthOf(String t) => (TextPainter(
                    text: TextSpan(text: t, style: style),
                    textDirection: Directionality.of(context),
                    textScaler: scaler,
                    maxLines: 1,
                  )..layout())
                      .width;
              // An even step on the clock (every hour, or every 2, 3, 4 or 6)
              // wide enough for the labels, so they read 8 · 10 · 12 · 2,
              // never 10 · 12 · 2 · 3. Each stretch's first hour is in full.
              final widest = widthOf(_hourShort(12)) + _minGap + 4;
              final step = const [1, 2, 3, 4, 6].firstWhere((n) => n * perHour >= widest, orElse: () => 6);
              final labels = <(double, String)>[];
              var right = double.negativeInfinity;
              for (final r in axis.runs) {
                for (var k = r.from; k < r.to; k++) {
                  if (k != r.from && k % step != 0) continue;
                  final text = k == r.from ? _hourFull(k) : _hourShort(k);
                  final left = axis.x(k.toDouble(), perHour, _breakPx) + 2;
                  final w = widthOf(text);
                  if (left < right + _minGap || left + w > view) continue;
                  labels.add((left, text));
                  right = left + w;
                }
              }
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Stack(clipBehavior: Clip.none, children: [
                  for (final (left, width) in axis.breaks(perHour, _breakPx))
                    if (left >= 1 && left + width <= view - 1)
                    Positioned(
                      left: left,
                      width: width,
                      top: 0,
                      bottom: 0,
                      child: const Center(child: Icon(Icons.more_vert_rounded, size: 13, color: LookUpColors.grey)),
                    ),
                  for (final (left, text) in labels) Positioned(left: left, child: Text(text, style: style)),
                ]),
              );
            }),
          ),
        ),
      ]));
}

/// "10 PM" (or "22:00"), for the first hour of a stretch.
String _hourFull(int k) => use24HourClock ? '${k.toString().padLeft(2, '0')}:00' : DateFormat.j().format(DateTime(2000, 1, 1, k));

/// "11", for the hours after it.
String _hourShort(int k) => use24HourClock ? '$k' : '${k % 12 == 0 ? 12 : k % 12}';

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
  const _NightBar(this.n,
      {required this.axis, required this.selected, required this.pick, required this.onNight, required this.onPick});
  final WeekNight n;
  final DayAxis axis;

  final bool selected;
  final SkyEvent? pick;
  final ValueChanged<DateTime> onNight;
  final ValueChanged<SkyEvent> onPick;

  static const _size = 24.0;
  static const _laneStep = _size + 3;

  /// The day's markers laid out for a bar [view] wide.
  static ({List<BarSlot> slots, List<double> labels}) layout(BuildContext context, WeekNight n, DayAxis axis, double view) {
    final perHour = _perHour(axis, view);
    final w = view;
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
    final slots = layoutBar(
      timeX: [for (final e in n.events) axis.x(hourOfDay(e.start), perHour, _breakPx)],
      namedWidth: [for (final l in labels) _Marker.widthFor(l)],
      width: w,
      icon: _size,
    );
    return (slots: slots, labels: labels);
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
          child: LayoutBuilder(builder: (context, box) {
            final view = box.maxWidth - 2; // inside the border
            final perHour = _perHour(axis, view);
            final laid = layout(context, n, axis, view);
            final slots = laid.slots;
            // One row tall unless this day's sights really pile up: a busy
            // day grows on its own, so the rest of the week stays in view.
            final rows = slots.isEmpty ? 1 : slots.map((s) => s.lane).reduce(math.max) + 1;
            final h = _barHeight + (rows - 1) * _laneStep;
            return Container(
              height: h,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: selected ? LookUpColors.blue.withValues(alpha: 0.7) : LookUpColors.line),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                    width: view,
                    height: h - 2,
                    child: Stack(children: [
                  Positioned.fill(child: CustomPaint(painter: _BarPainter(n.clouds, axis, perHour))),
                  // Each sight's exact time, behind every marker so a line
                  // never runs across another sight.
                  for (var i = 0; i < n.events.length; i++)
                    Positioned(
                      left: slots[i].tick - 1,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 2,
                        color: eventStyle(n.events[i].type, details: n.events[i].details)
                            .color
                            .withValues(alpha: n.events[i].type.pushes || n.events[i].id == pick?.id ? 0.55 : 0.3),
                      ),
                    ),
                  for (var i = 0; i < n.events.length; i++)
                    Positioned(
                      left: slots[i].left,
                      top: (_barHeight - _size) / 2 - 1 + slots[i].lane * _laneStep,
                      child: _Marker(n.events[i],
                          selected: n.events[i].id == pick?.id,
                          onTap: onPick,
                          labelWidth: slots[i].named ? laid.labels[i] : null),
                    ),
                    ]),
                  ),
              ),
            );
          }),
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
          : Icon(s.icon, size: 12.5, color: ink),
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
        child: Container(
          width: label == null ? _NightBar._size : widthFor(label),
          height: _NightBar._size,
          decoration: BoxDecoration(
            // Opaque even when faded, so a time line never shows through
            // another sight's marker.
            color: selected
                ? s.color
                : Color.alphaBlend(s.color.withValues(alpha: 0.24 * (e.type.pushes ? 1 : 0.5)), _barDark),
            borderRadius: BorderRadius.circular(6),
            border: selected ? Border.all(color: LookUpColors.white, width: 2) : null,
          ),
          child: Opacity(
            opacity: e.type.pushes || selected ? 1 : 0.5,
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

/// The shown hours (dim by day, dark by night) with cloud hatched in by the
/// hour, and the chopped stretches between them.
class _BarPainter extends CustomPainter {
  _BarPainter(this.clouds, this.axis, this.perHour);
  final List<int?> clouds; // 24, from midnight
  final DayAxis axis;
  final double perHour;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _barDark);
    final stripe = Paint()..strokeWidth = 1.4;
    for (final r in axis.runs) {
      for (var hour = r.from; hour < r.to; hour++) {
        final left = axis.x(hour.toDouble(), perHour, _breakPx);
        final cell = Rect.fromLTWH(left, 0, perHour + 0.5, size.height);
        // Daylight is lighter, the small hours darkest.
        final day = hour >= 7 && hour < 18;
        final dusk = hour == 6 || hour == 18 || hour == 19;
        canvas.drawRect(cell, Paint()..color = day ? const Color(0xFF22345F) : (dusk ? const Color(0xFF1B2A52) : _barDark));
        final c = clouds[hour];
        if (c == null || c < 50) continue;
        final a = ((c - 30) / 60).clamp(0.0, 1.0);
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
    // Where time was cut: a darker strip with a zig-zag down it, so it
    // reads as "hours skipped here", not as more of the night.
    final zig = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = LookUpColors.white.withValues(alpha: 0.22);
    for (final (left, width) in axis.breaks(perHour, _breakPx)) {
      // The day's own start and end, cut: just dark, no zig-zag (it's
      // plainly the edge of the day). Only hours skipped mid-day get one.
      final edge = left < 1 || left + width > size.width - 1;
      canvas.drawRect(Rect.fromLTWH(left, 0, width, size.height), Paint()..color = const Color(0xFF070B18));
      if (edge) continue;
      final mid = left + width / 2;
      final path = Path()..moveTo(mid - 2.5, 0);
      for (var y = 5.0, k = 1; y <= size.height + 5; y += 5, k++) {
        path.lineTo(mid + (k.isOdd ? 2.5 : -2.5), y);
      }
      canvas.drawPath(path, zig);
    }
  }

  @override
  bool shouldRepaint(_BarPainter o) => o.clouds != clouds || o.perHour != perHour || o.axis.runs != axis.runs;
}

/// The picked sight, in a few words; tap for the Look sheet.
class _PickCard extends StatelessWidget {
  const _PickCard(this.e, {required this.locked});
  final SkyEvent e;
  final bool locked;
  @override
  Widget build(BuildContext context) {
    // Last week's: what it was and how it went, not what to do.
    final past = e.end.isBefore(DateTime.now().toUtc());
    // Kept to two lines (what and when) so the week above has the room; the
    // rest is a tap away, on the Look sheet.
    return GlassCard(
        tint: eventStyle(e.type, details: e.details).color,
        onTap: () => showLookSheet(context, e),
        padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
        child: Row(children: [
          EventGlyph.of(e, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(past ? pastTitle(e) : eventTitle(e),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              Text(past ? pastVerdict(e) : '${fmtDay(e.start)}, ${fmtTime(e.start)}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: numeric(size: 12.5, color: LookUpColors.grey)),
            ]),
          ),
          if (!past && locked) ...[
            const SizedBox(width: 6),
            const PlusAlertTag(size: 12),
          ] else if (!past && !e.type.pushes) ...[
            const SizedBox(width: 6),
            const Text('No alert', style: TextStyle(fontSize: 12, color: LookUpColors.greyDim)),
          ],
          const Icon(Icons.chevron_right_rounded, color: LookUpColors.greyDim),
        ]),
      );
  }
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
