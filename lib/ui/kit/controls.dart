import 'package:flutter/material.dart';

import '../format.dart';
import '../theme.dart';

/// A small tinted capsule: a status ("Clear"), a tag ("LookUp+"), a planet.
class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.icon, this.color = LookUpColors.grey, this.dot = false});
  final String label;
  final IconData? icon;
  final Color color;

  /// A coloured dot in front instead of an icon.
  final bool dot;

  @override
  Widget build(BuildContext context) => Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(13)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (dot) ...[
            Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ] else if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
          ],
          Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color, letterSpacing: -0.1)),
        ]),
      );
}

/// Cloud cover as a status pill: green when clear, amber when patchy.
class CloudPill extends StatelessWidget {
  const CloudPill(this.cover, {super.key});
  final int? cover;

  @override
  Widget build(BuildContext context) {
    final c = cover;
    final (color, icon) = c == null
        ? (LookUpColors.greyDim, Icons.help_outline_rounded)
        : c <= 20
            ? (LookUpColors.good, Icons.nightlight_round)
            : c <= 60
                ? (LookUpColors.warn, Icons.cloud_queue_rounded)
                : (LookUpColors.grey, Icons.cloud_rounded);
    final word = cloudWord(c);
    return Pill(c == null ? 'No forecast' : '${word[0].toUpperCase()}${word.substring(1)}', icon: icon, color: color);
  }
}

/// A pill-shaped segmented control with a sliding thumb and optional counts.
class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({super.key, required this.labels, required this.index, required this.onSelect, this.counts});
  final List<String> labels;
  final List<int>? counts;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => Container(
        height: 42,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: LookUpColors.glass,
          borderRadius: BorderRadius.circular(21),
          border: Border.all(color: LookUpColors.line),
        ),
        child: LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth / labels.length;
          return Stack(children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              left: w * index,
              top: 0,
              bottom: 0,
              width: w,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: LookUpColors.glassStrong,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2))],
                ),
              ),
            ),
            Row(children: [
              for (final (i, l) in labels.indexed)
                Expanded(
                  child: Semantics(
                    selected: i == index,
                    button: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onSelect(i),
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(l,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.2,
                                    color: i == index ? LookUpColors.white : LookUpColors.grey,
                                  )),
                              if (counts != null) ...[
                                const SizedBox(width: 6),
                                Text('${counts![i]}',
                                    style: numeric(
                                        size: 12.5,
                                        weight: FontWeight.w600,
                                        color: i == index ? LookUpColors.blue : LookUpColors.greyDim)),
                              ],
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ]);
        }),
      );
}

/// A round translucent icon button for headers. [color] tints the icon;
/// [active] fills the circle with it, for toggles that are on.
class CircleButton extends StatelessWidget {
  const CircleButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 38,
    this.color = LookUpColors.white,
    this.active,
  });
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final Color color;

  /// Null for a plain button; true/false for a toggle.
  final bool? active;

  @override
  Widget build(BuildContext context) {
    final on = active ?? false;
    final button = Material(
      color: on ? color.withValues(alpha: 0.28) : LookUpColors.glass,
      shape: CircleBorder(side: BorderSide(color: on ? color.withValues(alpha: 0.7) : LookUpColors.line)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(width: size, height: size, child: Icon(icon, size: size * 0.5, color: color)),
      ),
    );
    return Semantics(
      button: true,
      toggled: active,
      label: tooltip,
      // The label replaces the icon's semantics, so the tap has to be
      // offered here or screen readers can't press it.
      onTap: onPressed,
      excludeSemantics: tooltip != null,
      child: tooltip == null ? button : Tooltip(message: tooltip!, child: button),
    );
  }
}

/// Label over a value over an optional muted line.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.k, required this.v, this.s, this.align = CrossAxisAlignment.start, this.valueColor});
  final String k;
  final String v;
  final String? s;
  final CrossAxisAlignment align;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: align,
        children: [
          Text(k, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: LookUpColors.grey)),
          const SizedBox(height: 4),
          Text(v, style: display(24, weight: FontWeight.w600, color: valueColor)),
          if (s != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(s!, style: numeric(size: 12.5, color: LookUpColors.grey)),
            ),
        ],
      );
}

/// "3h 12m" with the numbers big and the units small and muted, the way a
/// flight tracker shows time to departure.
class CountdownText extends StatelessWidget {
  const CountdownText(this.text, {super.key, this.size = 64, this.color = LookUpColors.white, this.unitColor});
  final String text;
  final double size;
  final Color color;
  final Color? unitColor;

  static final _token = RegExp(r'(\d+)|([^\d]+)');

  @override
  Widget build(BuildContext context) {
    final big = display(size, weight: FontWeight.w600, color: color, height: 1.0);
    final small = display(size * 0.46, weight: FontWeight.w500, color: unitColor ?? LookUpColors.grey, height: 1.0)
        .copyWith(letterSpacing: 0);
    return Text.rich(
      TextSpan(children: [
        for (final m in _token.allMatches(text)) TextSpan(text: m.group(0), style: m.group(1) != null ? big : small),
      ]),
      maxLines: 1,
    );
  }
}

/// A sideways-scrolling row of choice chips: nights, places.
class ChipRow extends StatelessWidget {
  const ChipRow({super.key, required this.labels, required this.index, required this.onSelect});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final (i, l) in labels.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Semantics(
              selected: i == index,
              button: true,
              child: Material(
                color: i == index ? LookUpColors.glassStrong : LookUpColors.glass,
                shape: StadiumBorder(side: BorderSide(color: i == index ? LookUpColors.blue : LookUpColors.line)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onSelect(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    child: Text(l,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: i == index ? LookUpColors.white : LookUpColors.grey,
                        )),
                  ),
                ),
              ),
            ),
          ],
        ]),
      );
}
