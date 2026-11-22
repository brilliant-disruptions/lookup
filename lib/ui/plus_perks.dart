/// Everything LookUp+ adds, in one list, so the paywall and the onboarding
/// offer can't drift apart. Keep in step with `domain/plus/free_plan.dart`
/// and `docs/plus-strategy.md`.
///
/// The sky through history isn't here: it's hidden in the app for now
/// (`skyThroughHistory` in `sky/sky_screen.dart`).
library;

import 'package:material_ui/material_ui.dart';

import 'kit/kit.dart';
import 'theme.dart';

typedef PlusPerk = ({String key, IconData icon, Color color, String short, String detail, String line});

const plusPerks = <PlusPerk>[
  (
    key: 'alerts',
    icon: Icons.notifications_active_rounded,
    color: LookUpColors.good,
    short: 'Every alert',
    detail: 'Aurora, Starlink, Tiangong, launches',
    line: 'Every alert: live aurora with a wake-me option, Starlink trains, Tiangong, rocket launches and comets',
  ),
  (
    key: 'camera',
    icon: Icons.camera_rounded,
    color: LookUpColors.violet,
    short: 'The Pro camera',
    detail: 'Best settings for Moon, stars, aurora',
    line: 'The Pro camera: the right lens, shutter and ISO for the Moon, planets, stars, meteors and aurora',
  ),
  (
    key: 'timelapse',
    icon: Icons.timelapse_rounded,
    color: LookUpColors.cyan,
    short: 'Self-starting timelapses',
    detail: 'Capture each event from beginning to end',
    line: 'Timelapses that start when it rises and stop when it sets',
  ),
  (
    key: 'whereToGo',
    icon: Icons.near_me_rounded,
    color: LookUpColors.blue,
    short: 'Where to go tonight',
    detail: 'Clearer, darker skies within a drive',
    line: 'Where to go tonight: clearer, darker skies within a drive',
  ),
  (
    key: 'planAhead',
    icon: Icons.calendar_month_rounded,
    color: LookUpColors.blue,
    short: '14 nights ahead',
    detail: 'See 14 nights, not just 3',
    line: 'Plan any of the next 14 nights, not just three',
  ),
  (
    key: 'places',
    icon: Icons.place_rounded,
    color: LookUpColors.gold,
    short: 'Save multiple locations',
    detail: 'Home, the cabin, the trip',
    line: 'As many saved places as you like: home, the cabin, the trip',
  ),
  (
    key: 'transits',
    icon: Icons.brightness_5_rounded,
    color: LookUpColors.orange,
    short: 'Station across the Sun',
    detail: 'Photo planning, and where to stand',
    line: 'Photo planning: the station crossing the Sun or Moon, and where to stand',
  ),
  (
    key: 'noCaption',
    icon: Icons.closed_caption_disabled_rounded,
    color: LookUpColors.grey,
    short: 'Photos without our caption',
    detail: 'Just the sky, if you like',
    line: 'Your photos without the LookUp caption, if you like',
  ),
];

/// The list, a line each (the paywall).
class PlusPerkList extends StatelessWidget {
  const PlusPerkList({super.key});
  @override
  Widget build(BuildContext context) => Column(children: [
        for (final p in plusPerks)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              EventGlyph(icon: p.icon, color: p.color, size: 26),
              const SizedBox(width: 12),
              Expanded(child: Text(p.line, style: const TextStyle(fontSize: 14.5, height: 1.3))),
            ]),
          ),
      ]);
}

/// The rest of LookUp+ as a small grid (the onboarding offer), leaving out
/// [except] (what the page has already said).
class PlusPerkGrid extends StatelessWidget {
  const PlusPerkGrid({super.key, this.except = const {}, this.detailed = false});
  final Set<String> except;

  /// A line under each name saying what it gives you (the paywall).
  final bool detailed;
  @override
  Widget build(BuildContext context) {
    final perks = [for (final p in plusPerks) if (!except.contains(p.key)) p];
    Widget tile(PlusPerk p) => Container(
          key: Key('perk-${p.key}'),
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
          decoration: BoxDecoration(color: LookUpColors.glass, borderRadius: BorderRadius.circular(Radii.md), border: Border.all(color: LookUpColors.line)),
          child: Row(children: [
            EventGlyph(icon: p.icon, color: p.color, size: 28),
            const SizedBox(width: 9),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.short, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.2)),
                if (detailed) ...[
                  const SizedBox(height: 2),
                  Text(p.detail, style: const TextStyle(fontSize: 11.5, height: 1.25, color: LookUpColors.grey)),
                ],
              ]),
            ),
          ]),
        );
    // Rows of two (no LayoutBuilder: pages around it measure their content).
    return Column(children: [
      for (var i = 0; i < perks.length; i += 2)
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: tile(perks[i])),
              const SizedBox(width: 8),
              Expanded(child: i + 1 < perks.length ? tile(perks[i + 1]) : const SizedBox()),
            ]),
          ),
        ),
    ]);
  }
}
