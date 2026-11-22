import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/plan_state.dart';
import '../../state/sky_state.dart';
import '../favourites_screen.dart';
import '../format.dart';
import '../kit/kit.dart';
import '../theme.dart';
import '../tonight_story.dart';
import 'sky_thing.dart';

/// What used to crowd the home screen, now where you go looking: the night
/// as a short story, and favourites. (The starter sights are on the Log.)
class SkyShortcuts extends ConsumerWidget {
  const SkyShortcuts({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GroupedList(indent: 64, children: [
          ListRow(
            leading: const EventGlyph(icon: Icons.play_arrow_rounded, color: LookUpColors.blue),
            title: 'Tonight in 20 seconds',
            subtitle: 'The whole night as a short story',
            subtitleLines: 1,
            onTap: () => showTonightStory(context),
          ),
          ListRow(
            leading: const EventGlyph(icon: Icons.favorite_rounded, color: LookUpColors.red),
            title: 'Your favourites',
            subtitle: _favouritesLine(ref),
            subtitleLines: 1,
            onTap: () => openFavourites(context),
          ),
        ]),
      ]);

  /// "Saturn tonight", "Saturn, Thursday", or how to start.
  static String _favouritesLine(WidgetRef ref) {
    final favourites = ref.watch(favouritesAheadProvider).value ?? const <FavouriteOutlook>[];
    if (favourites.isEmpty) return 'Tap \u2665 on anything in Explore to follow it';
    final catalog = ref.watch(skyCatalogProvider).value;
    final nights = ref.watch(nightsAheadProvider).value;
    final up = [for (final f in favourites) if (f.night != null) f]..sort((a, b) => a.night!.compareTo(b.night!));
    if (up.isEmpty) return 'None well placed in the next two weeks';
    String name(String id) => catalog == null ? 'One' : skyName(id, catalog);
    final tonight = up.where((f) => f.night == 0).toList();
    if (tonight.isNotEmpty) {
      return tonight.length == 1 ? '${name(tonight.first.id)} tonight' : '${name(tonight.first.id)} and ${tonight.length - 1} more tonight';
    }
    final next = up.first;
    final when = next.night == 1
        ? 'tomorrow night'
        : nights?[next.night!].window == null
            ? 'in ${next.night} nights'
            : fmtDay(nights![next.night!].window!.start);
    return 'Next: ${name(next.id)}, $when';
  }
}
