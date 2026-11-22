/// Every day as one bar, midnight to midnight ("At a glance"), in one list:
/// last week above, today in view, the two weeks ahead below. Hours with
/// nothing on anywhere are chopped out (`DayAxis`), leaving a narrow break.
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

/// Temporary: which proposed tweaks are on, for side-by-side renders.
abstract final class WeekLook {
  static bool compact = false, breaks = false, oneLine = false, edges = false;
}

/// "Fri" over "30", the selected night in blue.
class _NightLabel extends StatelessWidget {
  const _NightLabel(this.date, {required this.selected, this.past = false});
  final DateTime date;
  final bool selected, past;
  @override
  Widget build(BuildContext context) => WeekLook.oneLine ? _oneLine() : SizedBox(
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

  /// "Sun 22" on one line: the weekday bold, the date beside it.
  Widget _oneLine() => SizedBox(
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

/// Each night's bar, and the room between one night and the next.
double get _barHeight => WeekLook.compact ? 30.0 : 40.0;
double get _rowGap => WeekLook.compact ? 7.0 : 12.0;
const _barDark = Color(0xFF0D1530);

/// How many shown hours fit across the screen at once; swipe sideways for the
/// rest, so sights close together come apart. A chopped stretch is [_breakPx].
const _hoursInView = 6.0;
double get _breakPx => WeekLook.breaks ? 18.0 : 8.0;

/// The pixels one shown hour takes, for a bar [view] wide.
double _perHour(double view) => view / _hoursInView;

/// How far the bars can scroll sideways.
double _maxScroll(DayAxis axis, double view) => math.max(0.0, axis.width(_perHour(view), _breakPx) - view);

/// One horizontal scroll position shared by every night's bar and the hours
/// above them, so the nights stay lined up on the clock as you swipe.
class _SyncedH extends StatefulWidget {
  const _SyncedH({required this.offset, required this.child});
  final ValueNotifier<double> offset;
  final Widget child;
  @override
  State<_SyncedH> createState() => _SyncedHState();
}

class _SyncedHState extends State<_SyncedH> {
  late final ScrollController _c = ScrollController(initialScrollOffset: widget.offset.value)..addListener(_mine);

  void _mine() {
    if (_c.hasClients && (_c.offset - widget.offset.value).abs() > 0.5) {
      widget.offset.value = _c.offset;
    }
  }

  void _theirs() {
    if (!_c.hasClients) return;
    final to = widget.offset.value.clamp(_c.position.minScrollExtent, _c.position.maxScrollExtent);
    if ((_c.offset - to).abs() > 0.5) _c.jumpTo(to);
  }

  @override
  void initState() {
    super.initState();
    widget.offset.addListener(_theirs);
  }

  @override
  void dispose() {
    widget.offset.removeListener(_theirs);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        controller: _c,
        physics: const ClampingScrollPhysics(),
        child: widget.child,
      );
}

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
  bool _showPast = false;

  /// Where the hours are scrolled to, for every night at once.
  final _hours = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    // Opens on "Today and ahead"; "Last week" is the other tab.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _hours.value = _firstSightOffset();
    });
  }

  /// Open the hours on the first sight coming up, not on an empty 5 PM.
  double _firstSightOffset() {
    final view = MediaQuery.sizeOf(context).width - 32 - _labelWidth - _labelGap - 2;
    final axis = _axis;
    for (final n in widget.nights.where((n) => !n.past)) {
      if (n.events.isEmpty) continue;
      final x = n.events.map((e) => axis.x(hourOfDay(e.start), _perHour(view), _breakPx)).reduce(math.min);
      return (x - view * 0.4).clamp(0.0, _maxScroll(axis, view));
    }
    return 0;
  }

  /// One set of hours for every day, so the rows stay lined up on the clock.
  DayAxis get _axis => DayAxis.forStarts([
        for (final n in widget.nights)
          for (final e in n.events) e.start,
      ]);

  @override
  void dispose() {
    _hours.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Widget _row(WeekNight n, DayAxis axis, int lanes) => Padding(
        padding: EdgeInsets.only(bottom: _rowGap),
        child: Opacity(
          opacity: n.past ? 0.6 : 1,
          child: Row(children: [
            _NightLabel(n.date, selected: n.date == widget.night, past: n.past),
            const SizedBox(width: _labelGap),
            Expanded(
                child: _NightBar(n,
                    axis: axis,
                    lanes: lanes,
                    selected: n.date == widget.night,
                    pick: widget.pick,
                    hours: _hours,
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
    final view = MediaQuery.sizeOf(context).width - 32 - _labelWidth - _labelGap - 2;
    var lanes = 1;
    for (final n in widget.nights) {
      final slots = _NightBar.layout(context, n, axis, view).slots;
      if (slots.isNotEmpty) lanes = math.max(lanes, slots.map((s) => s.lane).reduce(math.max) + 1);
    }
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
              _Axis(_hours, axis),
              for (final n in past) _row(n, axis, lanes),
            ] else ...[
              if (past.isEmpty) const _Section('Today and ahead'),
              _Axis(_hours, axis),
              for (final n in ahead) _row(n, axis, lanes),
            ],
            const SizedBox(height: 6),
            const Wrap(spacing: 14, runSpacing: 6, children: [
              _Key(icon: Icons.swap_horiz_rounded, label: 'Swipe the hours sideways'),
              _Key(icon: Icons.dark_mode_outlined, label: 'Gaps: hours with nothing on'),
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
              padding: EdgeInsets.symmetric(vertical: WeekLook.compact ? 6 : 9),
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
      padding: WeekLook.compact ? const EdgeInsets.fromLTRB(0, 4, 0, 6) : const EdgeInsets.fromLTRB(0, 10, 0, 12),
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

/// The hours across the top of the bars.
class _Axis extends StatelessWidget {
  const _Axis(this.hours, this.axis);
  final ValueNotifier<double> hours;
  final DayAxis axis;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        const SizedBox(width: _labelWidth + _labelGap),
        Expanded(
          child: SizedBox(
            height: 16,
            child: LayoutBuilder(builder: (context, box) {
              final view = box.maxWidth - 2;
              final style = numeric(size: 10.5, color: LookUpColors.greyDim);
              String h(int hour) => DateFormat.j().format(DateTime(2000, 1, 1, hour));
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: _SyncedH(
                  offset: hours,
                  child: SizedBox(
                    width: axis.width(_perHour(view), _breakPx),
                    child: Stack(children: [
                      // Where hours were cut out: a "⋯" in the hours row, over the dotted line.
                      if (WeekLook.breaks)
                        for (final (left, width) in axis.breaks(_perHour(view), _breakPx))
                          Positioned(
                            left: left,
                            width: width,
                            top: 0,
                            child: Center(child: Text('···', style: style.copyWith(color: LookUpColors.grey, fontWeight: FontWeight.w800))),
                          ),
                      // Every hour that's shown; the chopped ones aren't.
                      for (final r in axis.runs)
                        for (var k = r.from; k < r.to; k++)
                          Positioned(
                              left: axis.x(k.toDouble(), _perHour(view), _breakPx) + 3,
                              child: Text(WeekLook.breaks && k > r.from ? _hShort(k) : h(k), style: style)),
                    ]),
                  ),
                ),
              );
            }),
          ),
        ),
      ]));
}

/// "5:12" (or "5:12 AM"): short enough for an edge pill.
String _timeShort(DateTime utc) => fmtTime(utc).replaceAll(RegExp(r'[\s\u202f]?[AP]M$'), '');

/// "1", "2" … within a run of hours, with AM/PM only where a run starts: the
/// row reads 12 AM · 1 · 2 · 3 · 4 ⋯ 10 AM.
String _hShort(int k) => '${k % 12 == 0 ? 12 : k % 12}';

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
      {required this.axis, required this.lanes, required this.selected, required this.pick, required this.hours, required this.onNight, required this.onPick});
  final WeekNight n;
  final DayAxis axis;

  /// Lanes the tallest day needs; every bar is this tall so they match.
  final int lanes;
  final ValueNotifier<double> hours;
  final bool selected;
  final SkyEvent? pick;
  final ValueChanged<DateTime> onNight;
  final ValueChanged<SkyEvent> onPick;

  static double get _size => WeekLook.compact ? 22.0 : 26.0;
  static double get _laneStep => _size + (WeekLook.compact ? 2 : 4);

  /// The day's markers laid out for a bar [view] wide.
  static ({List<BarSlot> slots, List<double> labels}) layout(BuildContext context, WeekNight n, DayAxis axis, double view) {
    final perHour = _perHour(view);
    final w = math.max(view, axis.width(perHour, _breakPx));
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

  /// Markers for the sights scrolled off either side: fanned in time order at
  /// that edge, nearest one on top. A tap names it and scrolls to its time.
  Widget _edgeMarkers(List<BarSlot> slots, double off, double view, double h) {
    const small = 0.78;
    final half = _size / 2;
    final before = <int>[], after = <int>[];
    for (var i = 0; i < n.events.length; i++) {
      final x = slots[i].tick - off; // where its time is in view
      if (x < -half) before.add(i);
      if (x > view + half) after.add(i);
    }
    if (before.isEmpty && after.isEmpty) return const SizedBox.shrink();
    double step(int count) => count < 2 ? 0 : math.min(9.0, view * 0.25 / (count - 1));
    Widget marker(int i, double left) => Positioned(
          left: left,
          top: (h - _size) / 2,
          child: Transform.scale(
            scale: small,
            child: _Marker(n.events[i], selected: n.events[i].id == pick?.id, onTap: (e) {
              onPick(e);
              hours.value = (slots[i].tick - view / 2).clamp(0.0, _maxScroll(axis, view));
            }),
          ),
        );
    if (WeekLook.edges) {
      // One pill per edge: the nearest sight that way, its time, and how many more.
      Widget pill(List<int> list, {required bool right}) {
        final i = right ? list.first : list.last; // nearest to the view
        final e = n.events[i];
        final s = eventStyle(e.type, details: e.details);
        final more = list.length - 1;
        final arrow = Icon(right ? Icons.chevron_right_rounded : Icons.chevron_left_rounded, size: 14, color: LookUpColors.grey);
        return Positioned(
          left: right ? null : 2,
          right: right ? 2 : null,
          top: (h - 22) / 2,
          child: GestureDetector(
            onTap: () {
              onPick(e);
              hours.value = (slots[i].tick - view / 2).clamp(0.0, _maxScroll(axis, view));
            },
            child: Container(
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: Color.alphaBlend(s.color.withValues(alpha: 0.22), _barDark),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: s.color.withValues(alpha: 0.45)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (!right) arrow,
                s.icon == null
                    ? SizedBox(width: 12, height: 12, child: PlanetMark(color: s.color))
                    : Icon(s.icon, size: 12, color: s.color),
                const SizedBox(width: 3),
                Text('${_timeShort(e.start)}${more > 0 ? ' +$more' : ''}',
                    style: numeric(size: 10.5, color: LookUpColors.white).copyWith(fontWeight: FontWeight.w600)),
                if (right) arrow,
              ]),
            ),
          ),
        );
      }

      return Stack(children: [
        if (before.isNotEmpty) pill(before, right: false),
        if (after.isNotEmpty) pill(after, right: true),
      ]);
    }
    final beforeStep = step(before.length), afterStep = step(after.length);
    return Stack(children: [
      // Furthest first, so the nearest ends up on top.
      for (var k = 0; k < before.length; k++) marker(before[k], 1 + k * beforeStep),
      for (var k = after.length - 1; k >= 0; k--)
        marker(after[k], view - _size - 1 - (after.length - 1 - k) * afterStep),
    ]);
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
            final perHour = _perHour(view);
            final laid = layout(context, n, axis, view);
            final slots = laid.slots;
            final h = _barHeight + (lanes - 1) * _laneStep; // the same for every day
            return Container(
              height: h,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: selected ? LookUpColors.blue.withValues(alpha: 0.7) : LookUpColors.line),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(children: [
                _SyncedH(
                  offset: hours,
                  child: SizedBox(
                    width: math.max(view, axis.width(perHour, _breakPx)),
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
                      top: (WeekLook.compact ? 4 : 6) + slots[i].lane * _laneStep,
                      child: _Marker(n.events[i],
                          selected: n.events[i].id == pick?.id,
                          onTap: onPick,
                          labelWidth: slots[i].named ? laid.labels[i] : null),
                    ),
                    ]),
                  ),
                ),
                // Sights whose time is scrolled out of sight wait at the
                // edge, small, until their time comes back into view.
                if (n.events.isNotEmpty)
                  Positioned.fill(
                    child: ValueListenableBuilder<double>(
                      valueListenable: hours,
                      builder: (context, off, _) => _edgeMarkers(slots, off, view, h - 2),
                    ),
                  ),
                ]),
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
    // Where time was cut: just a faint dotted line, no gap to speak of.
    final cut = Paint()
      ..color = LookUpColors.white.withValues(alpha: 0.16)
      ..strokeWidth = 1;
    for (final (left, width) in axis.breaks(perHour, _breakPx)) {
      if (WeekLook.breaks) {
        // A darker strip with a zig-zag: plainly "time skipped here".
        canvas.drawRect(Rect.fromLTWH(left, 0, width, size.height), Paint()..color = const Color(0xFF070B18));
        final zig = Path();
        final mid = left + width / 2;
        for (var y = 0.0; y <= size.height; y += 6) {
          final x = mid + ((y ~/ 6).isEven ? -3 : 3);
          y == 0 ? zig.moveTo(x, y) : zig.lineTo(x, y);
        }
        canvas.drawPath(zig, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = LookUpColors.white.withValues(alpha: 0.22));
        continue;
      }
      final x = left + width / 2;
      for (var y = 4.0; y < size.height - 2; y += 5) {
        canvas.drawLine(Offset(x, y), Offset(x, y + 2), cut);
      }
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
    if (WeekLook.compact) {
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
              Text('${fmtDay(e.start)}, ${fmtTime(e.start)}${!past && locked ? ' · LookUp+' : ''}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: numeric(size: 12.5, color: LookUpColors.grey)),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: LookUpColors.greyDim),
        ]),
      );
    }
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
