import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

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
  const AppHeader({super.key, required this.title, this.place, this.onPlaceTap, this.actions = const [], this.placeKey});
  final Widget title;
  final String? place;

  /// For a spotlight tour to find the place chip.
  final Key? placeKey;
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
          // The bar is one fixed line: its words grow a little with large
          // text, not without limit (the page below scales fully).
          child: MediaQuery.withClampedTextScaling(
           maxScaleFactor: 1.2,
           child: SizedBox(
            height: height,
            child: Row(children: [
              const SizedBox(width: 20),
              // The title keeps its width where it can; a long place name
              // shrinks first. (Flexible, so a narrow phone with large text
              // shortens the title instead of overflowing the bar.)
              Flexible(
                flex: 0,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
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
              ),
              const SizedBox(width: 12),
              Expanded(
                child: place == null
                    ? const SizedBox.shrink()
                    : Align(alignment: Alignment.centerRight, child: _PlaceChip(key: placeKey, place: place!, onTap: onPlaceTap)),
              ),
              for (final a in actions) ...[const SizedBox(width: 8), a],
              const SizedBox(width: 16),
            ]),
           ),
          ),
        ),
      );
}

class _PlaceChip extends StatelessWidget {
  const _PlaceChip({super.key, required this.place, this.onTap});
  final String place;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        // With three buttons beside it (Explore) there's no room for a
        // name: "Nas…" says nothing, so it becomes just the pin to tap.
        if (box.maxWidth < 96) {
          if (box.maxWidth < 40) return const SizedBox.shrink();
          return Semantics(
            button: onTap != null,
            label: 'Place: $place',
            child: Material(
              color: LookUpColors.glass,
              shape: const CircleBorder(side: BorderSide(color: LookUpColors.line)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: const SizedBox(
                    width: 38, height: 38, child: Icon(Icons.near_me_rounded, size: 16, color: LookUpColors.blue)),
              ),
            ),
          );
        }
        return _chip();
      });

  Widget _chip() => ConstrainedBox(
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
    // Every row is built (these pages are short lists of settings), so a
    // page can open scrolled to any section: a lazy list hasn't built what's
    // far below yet, and there's then nothing to scroll to.
    final list = ListView(
        padding: EdgeInsets.fromLTRB(16, top + 8, 16, pad.bottom + 32), scrollCacheExtent: const ScrollCacheExtent.pixels(6000), children: children);
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
  const TabItem(this.icon, this.label, {this.activeIcon, this.key});
  final IconData icon;

  /// For a spotlight tour to find the tab.
  final Key? key;
  final IconData? activeIcon;
  final String label;
}

/// A floating frosted capsule of tabs; the active one sits on a soft pill.
/// Use with `Scaffold(extendBody: true)` so pages scroll underneath.
class FloatingTabBar extends StatelessWidget {
  const FloatingTabBar({super.key, required this.tabs, required this.index, required this.onSelect, this.trailing});
  final List<TabItem> tabs;
  final int index;
  final ValueChanged<int> onSelect;

  /// Sits beside the capsule on the right as its own round button (Pip).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(child: _capsule()),
            if (trailing case final t?) ...[const SizedBox(width: 10), t],
          ]),
        ),
      );

  Widget _capsule() => DecoratedBox(
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
                      key: t.key,
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
                              // One line, shrunk to fit four tabs beside Pip, even with big text.
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(t.label,
                                      maxLines: 1,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: i == index ? LookUpColors.white : LookUpColors.grey,
                                      )),
                                ),
                              ),
                            ]),
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
          );
}

/// Bottom padding for a scrolling page that sits under [FloatingTabBar].
double tabBarClearance(BuildContext context) => MediaQuery.paddingOf(context).bottom + 24;
