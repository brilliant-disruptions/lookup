import 'package:flutter/material.dart';

import '../real_sky.dart';
import '../theme.dart';

/// The page behind every tab: night-blue fading to black, with the real
/// stars above you right now near the top ([RealSky]). Content sits on
/// [GlassCard]s over it.
class SkyBackdrop extends StatelessWidget {
  const SkyBackdrop({super.key, required this.child, this.stars = true, this.glow = LookUpColors.blue});
  final Widget child;
  final bool stars;

  /// A soft colour bloom in the top corner; the next event's tint on Tonight.
  final Color? glow;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [LookUpColors.night, LookUpColors.black],
            stops: [0, 0.62],
          ),
        ),
        child: Stack(fit: StackFit.passthrough, children: [
          if (glow != null)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0.9, -1.05),
                      radius: 1.1,
                      colors: [glow!.withValues(alpha: 0.16), glow!.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
            ),
          if (stars) const Positioned.fill(child: RealSky(maxOpacity: 0.55)),
          child,
        ]),
      );
}

/// A translucent rounded surface with a hairline edge. [tint] washes the
/// top-left corner in a colour (the hero card uses the event's tint).
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.tint,
    this.radius = Radii.lg,
    this.border = LookUpColors.line,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? tint;
  final double radius;
  final Color border;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    final t = tint;
    return Material(
      type: MaterialType.transparency,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: r,
          border: Border.all(color: border),
          color: t == null ? LookUpColors.glass : null,
          gradient: t == null
              ? null
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [t.withValues(alpha: 0.2), t.withValues(alpha: 0.05), LookUpColors.glass],
                  stops: const [0, 0.45, 1],
                ),
        ),
        child: InkWell(borderRadius: r, onTap: onTap, child: Padding(padding: padding, child: child)),
      ),
    );
  }
}

/// Rows on one card, split by inset hairlines (iOS-style inset grouped).
/// [indent] lines the divider up with the row titles.
class GroupedList extends StatelessWidget {
  const GroupedList({super.key, required this.children, this.indent = 16});
  final List<Widget> children;
  final double indent;

  @override
  Widget build(BuildContext context) => Material(
        color: LookUpColors.glass,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(Radii.lg)),
          side: BorderSide(color: LookUpColors.line),
        ),
        child: Column(children: [
          for (final (i, c) in children.indexed) ...[
            if (i > 0) Divider(indent: indent),
            c,
          ],
        ]),
      );
}

/// One row: optional leading glyph, title over a muted line, and a trailing
/// value, control or chevron.
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.title,
    this.leading,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.chevron,
    this.subtitleLines = 2,
    this.titleColor,
    this.padding = const EdgeInsets.fromLTRB(16, 13, 14, 13),
  });

  final String title;
  final Widget? leading;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Defaults to showing when the row is tappable and has no [trailing].
  final bool? chevron;
  final int subtitleLines;
  final Color? titleColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final showChevron = chevron ?? (onTap != null && trailing == null);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: padding,
          child: Row(children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: -0.2, color: titleColor ?? LookUpColors.white)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      maxLines: subtitleLines,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, height: 1.35, color: LookUpColors.grey)),
                ],
              ]),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            if (showChevron) ...[
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, size: 22, color: LookUpColors.greyDim),
            ],
          ]),
        ),
      ),
    );
  }
}

/// A section title with an optional action on the right. [small] is the
/// quieter grey label used above grouped settings.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction, this.small = false, this.padding});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final bool small;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding ?? (small ? const EdgeInsets.fromLTRB(16, 26, 16, 8) : const EdgeInsets.fromLTRB(4, 30, 4, 12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: small
                    ? const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: LookUpColors.grey)
                    : display(19, weight: FontWeight.w600),
              ),
            ),
          ),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              behavior: HitTestBehavior.opaque,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(action!, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: LookUpColors.blue)),
                const Icon(Icons.chevron_right_rounded, size: 18, color: LookUpColors.blue),
              ]),
            ),
        ]),
      );
}

/// A small coloured kicker above a card's headline: "Next up", "Live".
class Kicker extends StatelessWidget {
  const Kicker(this.text, {super.key, this.color = LookUpColors.grey, this.live = false});
  final String text;
  final Color color;

  /// Adds a glowing dot in front, for things happening right now.
  final bool live;

  @override
  Widget build(BuildContext context) {
    final label = Text(text, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: color, letterSpacing: -0.1));
    // Without the dot it's just text, so a long one ("Tomorrow morning · 12:09 AM"
    // at big text sizes) wraps instead of running off the edge.
    if (!live) return label;
    return Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 8)],
          ),
        ),
        const SizedBox(width: 7),
        Flexible(child: label),
      ]);
  }
}
