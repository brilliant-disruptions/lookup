import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/plan/night_plan.dart';
import '../domain/sky/direction.dart';
import '../state/plan_state.dart';
import '../state/providers.dart';
import '../state/sky_state.dart';
import 'format.dart';
import 'kit/kit.dart';
import 'paywall_sheet.dart';
import 'plan_screen.dart';
import 'sky/object_sheet.dart';
import 'sky/sky_thing.dart';
import 'theme.dart';

Future<void> openFavourites(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FavouritesScreen()));

/// What they follow, soonest first: tonight, or the next good night.
class FavouritesScreen extends ConsumerWidget {
  const FavouritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favourites = ref.watch(favouritesAheadProvider).value ?? const <FavouriteOutlook>[];
    final footnote = Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
      child: Text(
        favourites.isEmpty
            ? 'Open the Sky tab, tap a planet, the Moon or a constellation, and tap the heart. '
                  'It shows up here with its next good night.'
            : (ref.watch(settingsProvider).value?.isPlus ?? false)
            ? 'Tap the heart on anything in the Sky tab to add or remove it. We tap you when one is at its best on a '
                  'clear night, at most once a week each (Settings → What to tell me about).'
            : 'Tap the heart on anything in the Sky tab to add or remove it.',
        textAlign: TextAlign.center,
        style: const TextStyle(color: LookUpColors.greyDim, fontSize: 12.5, height: 1.4),
      ),
    );
    if (favourites.isEmpty) {
      return PageScaffold(
        title: 'Your favourites',
        children: [
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Nothing followed yet', style: display(22, weight: FontWeight.w600)),
                const SizedBox(height: 8),
                const Text(
                  'Follow the things you love seeing and we\'ll tell you their next good night.',
                  style: TextStyle(color: LookUpColors.grey, height: 1.45),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    ref.read(homeTabProvider.notifier).set(1);
                    Navigator.of(context).popUntil((r) => r.isFirst);
                  },
                  icon: const Icon(Icons.explore_rounded, size: 18),
                  label: const Text('Open the Sky tab'),
                ),
              ],
            ),
          ),
          footnote,
        ],
      );
    }
    final nights = ref.watch(nightsAheadProvider).value;
    final catalog = ref.watch(skyCatalogProvider).value;
    final s = ref.watch(settingsProvider).value;
    if (nights == null || catalog == null || s?.latitude == null) {
      return const PageScaffold(
        title: 'Your favourites',
        children: [
          Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }
    final things = <int, Map<String, SkyThing>>{};
    final sorted = [...favourites]..sort((a, b) => (a.night ?? nightsAhead).compareTo(b.night ?? nightsAhead));
    return PageScaffold(
      title: 'Your favourites',
      subtitle: 'Soonest first',
      children: [
        GroupedList(
          indent: 64,
          children: [
            for (final f in sorted)
              () {
                final night = f.night;
                final thing = night == null
                    ? null
                    : things.putIfAbsent(
                        night,
                        () => skyThingsOf(nights[night], s!.latitude!, s.longitude!, catalog),
                      )[f.id];
                return ListRow(
                  leading: glyphForId(f.id, dim: night == null),
                  title: skyName(f.id, catalog),
                  titleColor: night == null ? LookUpColors.grey : null,
                  subtitle: favouriteWhen(f, night == null ? null : nights[night]),
                  subtitleLines: 1,
                  trailing: night == 0 ? const Pill('Tonight', dot: true, color: LookUpColors.good) : null,
                  chevron: night != null,
                  onTap: night == null
                      ? null
                      : night == 0 && thing != null
                      ? () => showObjectSheet(context, thing)
                      : () => openPlan(context, night: night),
                );
              }(),
          ],
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: PlusNudge(
            'Get a tap when one\'s at its best on a clear night',
            because: 'LookUp+ taps you when something you follow is at its best and the sky is clear.',
          ),
        ),
        footnote,
      ],
    );
  }
}

/// "Tonight · best 9:40 PM, southeast", "Thursday · best 4:10 AM, east".
String favouriteWhen(FavouriteOutlook f, NightPlan? plan) {
  final s = f.sighting;
  if (f.night == null || s == null) return 'Not well placed in the next two weeks';
  final day = switch (f.night!) {
    0 => 'Tonight',
    1 => 'Tomorrow night',
    _ => plan?.window == null ? 'In ${f.night} nights' : fmtDay(plan!.window!.start),
  };
  return '$day · best ${fmtTime(s.best)}, ${compassWord(s.azDeg)}';
}
