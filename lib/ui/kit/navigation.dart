import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'controls.dart';
import 'surfaces.dart';

/// Frosted glass for bars that content scrolls under.
class _Frost extends StatelessWidget {
  const _Frost({required this.child, this.border, this.radius});
  final Widget child;
  final Border? border;
  final BorderRadius? radius;

  @override
  Widget build(BuildContext context) {
    final body = BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: LookUpColors.panel.withValues(alpha: radius == null ? 0.62 : 0.74),
          border: border,
          borderRadius: radius,
        ),
        child: child,
      ),
    );
    return radius == null ? ClipRect(child: body) : ClipRRect(borderRadius: radius!, child: body);
  }
}

/// Header for the four tab roots: a large left-aligned title, the place
/// you're watching as a chip (tap to switch), then round actions.
class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  const AppHeader({super.key, required this.title, this.place, this.onPlaceTap, this.actions = const []});
  final Widget title;
  final String? place;
  final VoidCallback? onPlaceTap;
  final List<Widget> actions;

  static const height = 60.0;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) => _Frost(
        border: const Border(bottom: BorderSide(color: Color(0x0FFFFFFF))),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: height,
            child: Row(children: [
              const SizedBox(width: 20),
              Expanded(
                child: Semantics(
                  header: true,
                  child: DefaultTextStyle.merge(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: display(28, weight: FontWeight.w700),
                    child: title,
                  ),
                ),
              ),
              if (place != null) _PlaceChip(place: place!, onTap: onPlaceTap),
              for (final a in actions) ...[const SizedBox(width: 8), a],
              const SizedBox(width: 16),
            ]),
          ),
        ),
      );
}

class _PlaceChip extends StatelessWidget {
  const _PlaceChip({required this.place, this.onTap});
  final String place;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 170),
        child: Material(
          color: LookUpColors.glass,
          shape: const StadiumBorder(side: BorderSide(color: LookUpColors.line)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.near_me_rounded, size: 14, color: LookUpColors.blue),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(place,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: -0.1)),
                ),
                if (onTap != null) const Icon(Icons.expand_more_rounded, size: 18, color: LookUpColors.grey),
              ]),
            ),
          ),
        ),
      );
}

/// Header for pushed pages: round back button, centred title.
class PageHeader extends StatelessWidget implements PreferredSizeWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Size get preferredSize => const Size.fromHeight(58);

  @override
  Widget build(BuildContext context) {
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    return _Frost(
      border: const Border(bottom: BorderSide(color: Color(0x0FFFFFFF))),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: preferredSize.height,
          child: Row(children: [
            SizedBox(
              width: 64,
              child: canPop
                  ? Center(
                      child: CircleButton(
                        tooltip: 'Back',
                        icon: Icons.arrow_back_ios_new_rounded,
                        size: 36,
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    )
                  : null,
            ),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.3)),
                if (subtitle != null)
                  Text(subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: LookUpColors.grey)),
              ]),
            ),
            SizedBox(width: 64, child: trailing),
          ]),
        ),
      ),
    );
  }
}

/// A pushed page: [PageHeader] over the sky gradient, with a padded list.
class PageScaffold extends StatelessWidget {
  const PageScaffold({super.key, required this.title, this.subtitle, required this.children, this.onRefresh});
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final header = PageHeader(title: title, subtitle: subtitle);
    final top = pad.top + header.preferredSize.height;
    final list = ListView(padding: EdgeInsets.fromLTRB(16, top + 8, 16, pad.bottom + 32), children: children);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: header,
      body: SkyBackdrop(
        stars: false,
        glow: null,
        child: onRefresh == null ? list : RefreshIndicator(edgeOffset: top, onRefresh: onRefresh!, child: list),
      ),
    );
  }
}

class TabItem {
  const TabItem(this.icon, this.label, {this.activeIcon});
  final IconData icon;
  final IconData? activeIcon;
  final String label;
}

/// A floating frosted capsule of tabs; the active one sits on a soft pill.
/// Use with `Scaffold(extendBody: true)` so pages scroll underneath.
class FloatingTabBar extends StatelessWidget {
  const FloatingTabBar({super.key, required this.tabs, required this.index, required this.onSelect});
  final List<TabItem> tabs;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 30, offset: Offset(0, 10))],
            ),
            child: _Frost(
              radius: BorderRadius.circular(32),
              border: Border.all(color: LookUpColors.line),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Row(children: [
                  for (final (i, t) in tabs.indexed)
                    Expanded(
                      child: Semantics(
                        selected: i == index,
                        button: true,
                        label: t.label,
                        excludeSemantics: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onSelect(i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            height: 54,
                            decoration: BoxDecoration(
                              color: i == index ? LookUpColors.glassStrong : Colors.transparent,
                              borderRadius: BorderRadius.circular(27),
                            ),
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(i == index ? (t.activeIcon ?? t.icon) : t.icon,
                                  size: 22, color: i == index ? LookUpColors.blue : LookUpColors.grey),
                              const SizedBox(height: 3),
                              Text(t.label,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: i == index ? LookUpColors.white : LookUpColors.grey,
                                  )),
                            ]),
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
      );
}

/// Bottom padding for a scrolling page that sits under [FloatingTabBar].
double tabBarClearance(BuildContext context) => MediaQuery.paddingOf(context).bottom + 24;
