/// Elements borrowed from Woven's guest app (app-ideas/bloved), translated
/// to night: the frosted bottom tab bar (`.g-nav`), the compact centred
/// header, Dearly's underlined tabs (`.dly-tabs`), the guest timeline
/// (`.gx-tl`) and hairline-separated rows (`.gx-member`).
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Frosted glass: 92% panel over an 8 px blur, like Woven's sticky bars.
class _Frost extends StatelessWidget {
  const _Frost({required this.child, required this.border});
  final Widget child;
  final Border border;
  @override
  Widget build(BuildContext context) => ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: DecoratedBox(
            decoration: BoxDecoration(color: LookUpColors.black.withValues(alpha: 0.86), border: border),
            child: child,
          ),
        ),
      );
}

class WovenTab {
  const WovenTab(this.icon, this.label, {this.activeIcon});
  final IconData icon;
  final IconData? activeIcon;
  final String label;
}

/// Bottom tabs: hairline on top, thin icons over small labels, the active
/// one in colour. No pill, no indicator: Woven keeps it quiet.
class WovenNavBar extends StatelessWidget {
  const WovenNavBar({super.key, required this.tabs, required this.index, required this.onSelect});
  final List<WovenTab> tabs;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => _Frost(
        border: const Border(top: BorderSide(color: LookUpColors.line)),
        child: SafeArea(
          top: false,
          child: Row(children: [
            for (final (i, t) in tabs.indexed)
              Expanded(
                child: Semantics(
                  selected: i == index,
                  button: true,
                  label: t.label,
                  excludeSemantics: true,
                  child: InkResponse(
                    onTap: () => onSelect(i),
                    highlightShape: BoxShape.rectangle,
                    containedInkWell: true,
                    child: SizedBox(
                      height: 56,
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(i == index ? (t.activeIcon ?? t.icon) : t.icon,
                            size: 22, color: i == index ? LookUpColors.blue : LookUpColors.greyDim),
                        const SizedBox(height: 3),
                        Text(t.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                              color: i == index ? LookUpColors.blue : LookUpColors.greyDim,
                            )),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      );
}

/// Compact sticky header: serif title over a small muted line, centred,
/// frosted, hairline underneath.
class WovenHeader extends StatelessWidget implements PreferredSizeWidget {
  const WovenHeader({super.key, required this.title, this.subtitle, this.leading, this.trailing, this.onSubtitleTap});
  final Widget title;
  final String? subtitle;
  final VoidCallback? onSubtitleTap;
  final Widget? leading;
  final Widget? trailing;

  @override
  Size get preferredSize => const Size.fromHeight(58);

  @override
  Widget build(BuildContext context) {
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    final lead = leading ??
        (canPop
            ? IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null);
    return _Frost(
      border: const Border(bottom: BorderSide(color: LookUpColors.line)),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: preferredSize.height,
          child: Row(children: [
            SizedBox(width: 56, child: lead),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                DefaultTextStyle.merge(
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: displaySerif(context, size: 21, weight: FontWeight.w600),
                  child: title,
                ),
                if (subtitle != null)
                  GestureDetector(
                    onTap: onSubtitleTap,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5, color: LookUpColors.grey)),
                        if (onSubtitleTap != null)
                          const Icon(Icons.expand_more, size: 14, color: LookUpColors.greyDim),
                      ]),
                    ),
                  ),
              ]),
            ),
            SizedBox(width: 56, child: trailing),
          ]),
        ),
      ),
    );
  }
}

/// Dearly's underlined tabs, with optional counts.
class WovenTabs extends StatelessWidget {
  const WovenTabs({super.key, required this.labels, required this.index, required this.onSelect, this.counts});
  final List<String> labels;
  final List<int>? counts;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: LookUpColors.line))),
        child: Row(children: [
          for (final (i, l) in labels.indexed)
            Semantics(
              selected: i == index,
              button: true,
              child: InkWell(
                onTap: () => onSelect(i),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: i == index ? LookUpColors.blue : Colors.transparent, width: 2),
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(l,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: i == index ? LookUpColors.white : LookUpColors.greyDim,
                        )),
                    if (counts != null) ...[
                      const SizedBox(width: 6),
                      Text('${counts![i]}', style: monoData(context, size: 11, color: LookUpColors.greyDim)),
                    ],
                  ]),
                ),
              ),
            ),
        ]),
      );
}

/// One stop on a [WovenTimeline]. [now] fills the dot and gives it a halo.
class WovenTimelineItem {
  const WovenTimelineItem({required this.child, this.now = false, this.dim = false});
  final Widget child;
  final bool now;
  final bool dim;
}

/// Vertical line with hollow dots, like Woven's day-of schedule.
class WovenTimeline extends StatelessWidget {
  const WovenTimeline({super.key, required this.items});
  final List<WovenTimelineItem> items;

  @override
  Widget build(BuildContext context) => Column(children: [
        for (final (i, it) in items.indexed)
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 26,
                child: CustomPaint(
                  painter: _TimelineRail(first: i == 0, last: i == items.length - 1, now: it.now, dim: it.dim),
                ),
              ),
              Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 22), child: it.child)),
            ]),
          ),
      ]);
}

class _TimelineRail extends CustomPainter {
  _TimelineRail({required this.first, required this.last, required this.now, required this.dim});
  final bool first, last, now, dim;

  @override
  void paint(Canvas canvas, Size size) {
    const x = 6.5, dotY = 10.5, r = 6.5;
    final rail = Paint()
      ..color = LookUpColors.line
      ..strokeWidth = 1.5;
    if (!first) canvas.drawLine(const Offset(x, 0), const Offset(x, dotY - r), rail);
    if (!last) canvas.drawLine(const Offset(x, dotY + r), Offset(x, size.height), rail);
    final accent = dim ? LookUpColors.greyDim : LookUpColors.blue;
    if (now) {
      canvas.drawCircle(const Offset(x, dotY), r + 4, Paint()..color = LookUpColors.blue.withValues(alpha: 0.22));
      canvas.drawCircle(const Offset(x, dotY), r, Paint()..color = LookUpColors.blue);
    } else {
      canvas.drawCircle(const Offset(x, dotY), r - 1, Paint()..color = LookUpColors.black);
      canvas.drawCircle(
          const Offset(x, dotY),
          r - 1,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = accent);
    }
  }

  @override
  bool shouldRepaint(_TimelineRail o) => o.first != first || o.last != last || o.now != now || o.dim != dim;
}

/// Rows separated by hairlines, no cards: Woven's member list.
class WovenRows extends StatelessWidget {
  const WovenRows({super.key, required this.children, this.padding = const EdgeInsets.symmetric(horizontal: 16)});
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Column(children: [
          for (final (i, c) in children.indexed)
            DecoratedBox(
              decoration: BoxDecoration(
                border: i == 0 ? null : const Border(top: BorderSide(color: LookUpColors.line)),
              ),
              child: c,
            ),
        ]),
      );
}
