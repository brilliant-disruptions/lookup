/// Explore's opening card: the few things most worth looking for tonight,
/// each a tap from being found. It starts closed, a line saying what's up
/// ("Saturn, the Moon and 3 more"), so the sky map stays at the top; a tap
/// opens the list. Anything up right now gets "Show me", which hands over to
/// Pip in the camera; the rest say when they're best.
library;

import 'package:material_ui/material_ui.dart';

import '../../domain/sky/direction.dart';
import '../kit/kit.dart';
import '../theme.dart';
import 'sky_thing.dart';

/// Up and dark enough at [now], by tonight's reckoning: worth pointing the
/// phone at this minute.
bool upNow(SkyThing x, DateTime now) {
  final s = x.sighting;
  final from = s?.visibleFrom, to = s?.visibleTo;
  if (!x.seeable || from == null || to == null) return false;
  final n = now.toUtc();
  return !n.isBefore(from) && !n.isAfter(to) && x.position(n).altitudeDeg > 5;
}

/// At most [max] things to look for tonight, only ones tonight's verdict
/// says can be seen: the Moon, the planets (brightest first), then a couple
/// of showpieces and star patterns. Whatever is up right now comes first;
/// the rest follow in the order they're best tonight.
List<SkyThing> tonightsBest({
  required SkyThing moon,
  required List<SkyThing> planets,
  required List<SkyThing> showpieces,
  required List<SkyThing> constellations,
  required DateTime now,
  int max = 5,
}) {
  List<SkyThing> seen(List<SkyThing> xs) => [for (final x in xs) if (x.seeable) x];
  List<SkyThing> brightest(List<SkyThing> xs) => seen(xs)..sort((a, b) => a.mag.compareTo(b.mag));
  final picks = [
    ...seen([moon]),
    ...brightest(planets),
    ...brightest(showpieces).take(2),
    ...seen(constellations).take(2),
  ].take(max).toList();
  // Later ones in the order they come round, so the list reads like the night.
  final later = [for (final x in picks) if (!upNow(x, now)) x]
    ..sort((a, b) => a.sighting!.best.compareTo(b.sighting!.best));
  return [
    for (final x in picks) if (upNow(x, now)) x,
    ...later,
  ];
}

class UpTonightCard extends StatefulWidget {
  const UpTonightCard({
    super.key,
    required this.things,
    required this.now,
    required this.onOpen,
    required this.onShow,
    this.clouds,
    this.initiallyOpen = false,
  });
  final List<SkyThing> things;
  final DateTime now;

  /// Tonight's clouds in a few words ("Clear until 6:00 AM"), when there's a forecast.
  final String? clouds;

  /// Its sheet: what it is, when and where.
  final ValueChanged<SkyThing> onOpen;

  /// Pip leads the way to it in the camera.
  final ValueChanged<SkyThing> onShow;

  /// Closed to start with, so the sky map stays at the top of Explore.
  final bool initiallyOpen;

  /// "Saturn, the Moon and 3 more": the closed card in a line.
  static String summary(List<SkyThing> things) {
    String name(SkyThing x) => x.name.startsWith('The ') ? 'the ${x.name.substring(4)}' : x.name;
    return switch (things.length) {
      0 => 'Nothing well placed tonight',
      1 => things.first.name,
      2 => '${things.first.name} and ${name(things[1])}',
      _ => '${things.first.name}, ${name(things[1])} and ${things.length - 2} more',
    };
  }

  @override
  State<UpTonightCard> createState() => _UpTonightCardState();
}

class _UpTonightCardState extends State<UpTonightCard> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final things = widget.things;
    final upCount = things.where((x) => upNow(x, widget.now)).length;
    return GlassCard(
      key: const Key('up-tonight'),
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          button: true,
          expanded: _open,
          child: InkWell(
            key: const Key('up-tonight-toggle'),
            borderRadius: BorderRadius.circular(Radii.lg),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Kicker('Up tonight', color: LookUpColors.blue),
                      if (upCount > 0) ...[
                        const SizedBox(width: 10),
                        Kicker('$upCount up now', color: LookUpColors.good, live: true),
                      ],
                    ]),
                    const SizedBox(height: 4),
                    Text(UpTonightCard.summary(things),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: display(18, weight: FontWeight.w700)),
                    if (widget.clouds case final c?) ...[
                      const SizedBox(height: 2),
                      Text(c, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, color: LookUpColors.grey)),
                    ],
                  ]),
                ),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more_rounded, color: LookUpColors.grey),
                ),
                const SizedBox(width: 4),
              ]),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !_open
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 12, 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (things.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 10, right: 6),
                        child: Text(
                            'The map below still shows what\'s over you. LookUp will tap you when something is worth stepping out for.',
                            style: TextStyle(color: LookUpColors.grey, height: 1.45)),
                      ),
                    for (final x in things)
                      _Pick(x,
                          now: widget.now,
                          up: upNow(x, widget.now),
                          onOpen: () => widget.onOpen(x),
                          onShow: () => widget.onShow(x)),
                  ]),
                ),
        ),
      ]),
    );
  }
}

class _Pick extends StatelessWidget {
  const _Pick(this.x, {required this.now, required this.up, required this.onOpen, required this.onShow});
  final SkyThing x;
  final DateTime now;
  final bool up;
  final VoidCallback onOpen, onShow;

  @override
  Widget build(BuildContext context) {
    final where = x.sighting == null ? null : compassWord(x.position(now.toUtc()).azimuthDeg);
    return InkWell(
      key: Key('up-tonight-${x.id}'),
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(children: [
          thingGlyph(x),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(x.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(up && where != null ? 'Up now, in the $where' : x.status,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, color: LookUpColors.grey)),
            ]),
          ),
          const SizedBox(width: 8),
          if (up)
            FilledButton(
              onPressed: onShow,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 38),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Show me'),
            )
          else
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Icon(Icons.chevron_right_rounded, color: LookUpColors.greyDim),
            ),
        ]),
      ),
    );
  }
}
