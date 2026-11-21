/// Every night as one bar from 5 PM to 7 AM ("At a glance"), in one list:
/// last week above, tonight in view, the two weeks ahead below.
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
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

/// "Fri" over "30", the selected night in blue.
class _NightLabel extends StatelessWidget {
  const _NightLabel(this.date, {required this.selected, this.past = false});
  final DateTime date;
  final bool selected, past;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: _labelWidth,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(DateFormat.E().format(date),
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? LookUpColors.blue : (past ? LookUpColors.grey : LookUpColors.white))),
          const SizedBox(height: 1),
          Text(DateFormat.MMMd().format(date), style: numeric(size: 11, color: LookUpColors.greyDim)),
        ]),
      );
}

/// The day column, and the gap between it and the bars.
const _labelWidth = 48.0, _labelGap = 10.0;

/// Each night's bar, and the room between one night and the next.
const _barHeight = 40.0, _rowGap = 12.0;

/// Every night as one bar from 5 PM to 7 AM: cloud shaded in, a marker at
/// each sight's time. Last week sits above (faded, what went over), tonight
/// opens in view, and the nights ahead run on below. Tap one for its
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
  final _tonight = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Open on tonight, with last week a scroll up.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _tonight.currentContext;
      if (c != null && mounted) Scrollable.ensureVisible(c);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Widget _row(WeekNight n) => Padding(
        padding: const EdgeInsets.only(bottom: _rowGap),
        child: Opacity(
          opacity: n.past ? 0.6 : 1,
          child: Row(children: [
            _NightLabel(n.date, selected: n.date == widget.night, past: n.past),
            const SizedBox(width: _labelGap),
            Expanded(
                child: _NightBar(n,
                    selected: n.date == widget.night, pick: widget.pick, onNight: widget.onNight, onPick: widget.onPick)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final past = widget.nights.where((n) => n.past).toList();
    final ahead = widget.nights.where((n) => !n.past).toList();
    final pick = widget.pick;
    return Column(children: [
      const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: _Axis()),
      const SizedBox(height: 8),
      Expanded(
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            if (past.isNotEmpty) ...[
              const _Section('Last week'),
              if (widget.missed case final m?) Padding(padding: const EdgeInsets.only(bottom: 14), child: m),
              for (final n in past) _row(n),
            ],
            _Section('Tonight and ahead', key: _tonight),
            for (final n in ahead) _row(n),
            const SizedBox(height: 6),
            const Wrap(spacing: 14, runSpacing: 6, children: [
              _Key(icon: Icons.dark_mode_outlined, label: 'Dark band is the night'),
              _Key(icon: Icons.texture_rounded, label: 'Cloud'),
              _Key(icon: Icons.circle_outlined, label: 'Faded: no alert'),
            ]),
            const SizedBox(height: 18),
            const WeekTools(),
          ],
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

/// "Last week", "Tonight and ahead": where you are in the list.
class _Section extends StatelessWidget {
  const _Section(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 12),
        child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: LookUpColors.grey)),
      );
}

/// The hours across the top of the bars.
class _Axis extends StatelessWidget {
  const _Axis();
  @override
  Widget build(BuildContext context) => Row(children: [
        const SizedBox(width: _labelWidth + _labelGap),
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

  static const _size = 26.0;

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
            height: _barHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
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
                      top: (_barHeight - 2 - _size) / 2,
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
  Widget build(BuildContext context) {
    // Last week's: what it was and how it went, not what to do.
    final past = e.end.isBefore(DateTime.now().toUtc());
    return GlassCard(
        tint: eventStyle(e.type, details: e.details).color,
        onTap: () => showLookSheet(context, e),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          EventGlyph.of(e, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(past ? pastTitle(e) : eventTitle(e), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 1),
              Text('${fmtDay(e.start)}, ${fmtTime(e.start)}', style: numeric(size: 12.5, color: LookUpColors.grey)),
              const SizedBox(height: 4),
              Text(past ? pastVerdict(e) : eventSubtitle(e),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: LookUpColors.grey, height: 1.35)),
              if (!past && locked) ...[
                const SizedBox(height: 6),
                const PlusAlertTag(size: 12),
              ] else if (!past && !e.type.pushes) ...[
                const SizedBox(height: 6),
                const Text('No alert', style: TextStyle(fontSize: 12, color: LookUpColors.greyDim)),
              ],
            ]),
          ),
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
