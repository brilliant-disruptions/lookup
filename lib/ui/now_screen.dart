import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/sky_event.dart';
import '../domain/plan/where_to_go.dart';
import '../domain/sky/skyglow.dart';
import '../domain/sky/visibility.dart';
import '../services/location_service.dart';
import '../state/providers.dart';
import '../state/plan_state.dart';
import '../state/sky_state.dart';
import 'demo.dart';
import 'favourites_screen.dart';
import 'format.dart';
import 'kit/kit.dart';
import 'look_sheet.dart';
import 'places_screen.dart';
import 'plus_card.dart';
import 'settings_screen.dart';
import 'sky/sky_camera_screen.dart';
import 'sky/sky_thing.dart';
import 'starter_card.dart';
import 'theme.dart';
import 'tonight_story.dart';
import 'tour.dart';
import 'verdict_card.dart';
import 'where_to_go_screen.dart';

class NowScreen extends ConsumerWidget {
  const NowScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(homeProvider);
    final settings = ref.watch(settingsProvider).value;
    final place = (settings?.placeName?.isNotEmpty ?? false) ? settings!.placeName! : 'Near you';
    final top = MediaQuery.paddingOf(context).top + AppHeader.height;
    final next = home.value?.next;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppHeader(
        title: const _Wordmark(),
        place: place,
        placeKey: TourKeys.place,
        onPlaceTap: () => openPlaces(context),
        actions: [
          CircleButton(
            tooltip: 'Sky through your camera',
            icon: Icons.photo_camera_rounded,
            onPressed: () => openLiveSkyCamera(context, ref),
          ),
          KeyedSubtree(
            key: TourKeys.settings,
            child: CircleButton(tooltip: 'Settings', icon: Icons.settings_outlined, onPressed: () => openSettings(context)),
          ),
        ],
      ),
      body: SkyBackdrop(
        glow: next == null ? LookUpColors.blue : eventStyle(next.type, details: next.details).color,
        child: RefreshIndicator(
          edgeOffset: top,
          onRefresh: () => ref.read(homeProvider.notifier).refresh(force: true),
          child: home.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text('$e'))]),
            data: (d) => ListView(
              padding: EdgeInsets.fromLTRB(16, top + 14, 16, tabBarClearance(context)),
              children: [
                if (ref.watch(alertsEnabledProvider).value == false && !d.needsLocation)
                  const Padding(padding: EdgeInsets.only(bottom: 12), child: _AlertsOffCard()),
                Rise(
                  index: 0,
                  child: KeyedSubtree(
                    key: TourKeys.next,
                    child: d.needsLocation
                      ? const _LocationCard()
                      : d.noData
                          ? _OfflineCard(onRetry: () => ref.read(homeProvider.notifier).refresh(force: true))
                          : (d.next == null || d.next!.details['lookahead'] == true)
                              ? _QuietCard(nextBeyond: d.next)
                              : VerdictCard(home: d),
                  ),
                ),
                // New users: three things to find, so there's something to do tonight.
                if (!d.needsLocation) const Rise(index: 1, child: StarterSkyCard()),
                // Free users: what LookUp+ would add here, quietly, in the list.
                if (!d.needsLocation) const Rise(index: 1, child: PlusNearYouCard()),
                if (d.auroraOutlook != null) ...[
                  const SizedBox(height: 12),
                  Rise(index: 1, child: _OutlookCard(d.auroraOutlook!)),
                ],
                if (!d.needsLocation) const _MoreTonight(),
                if (d.next?.details['lookahead'] != true) ..._later(context, ref, d),
                if (d.errors.isNotEmpty && !d.needsLocation)
                  const Padding(
                    padding: EdgeInsets.only(top: 20),
                    child: Text('Couldn\'t refresh everything. Showing the last good copy.',
                        textAlign: TextAlign.center, style: TextStyle(color: LookUpColors.greyDim, fontSize: 12.5)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The next two things after the hero, as rows, and a way to the week.
  List<Widget> _later(BuildContext context, WidgetRef ref, HomeData d) {
    final rest = d.events.where((e) => e.id != d.next?.id && e.type.pushes).take(2).toList();
    if (rest.isEmpty) return const [];
    return [
      SectionHeader('Later', action: 'See all', onAction: () => ref.read(homeTabProvider.notifier).set(2)),
      Rise(
        index: 3,
        child: GroupedList(indent: 64, children: [
          for (final e in rest)
            ListRow(
              leading: EventGlyph.of(e),
              title: eventTitle(e),
              subtitle: '${fmtDay(e.start)}, ${fmtTime(e.start)}',
              trailing: CloudPill(e.cloudCoverPercent),
              onTap: () => showLookSheet(context, e),
            ),
        ]),
      ),
    ];
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();
  @override
  Widget build(BuildContext context) =>
      Text.rich(TextSpan(text: 'LookUp', children: [TextSpan(text: '.', style: TextStyle(color: LookUpColors.blue))]));
}

class _OutlookCard extends StatelessWidget {
  const _OutlookCard(this.e);
  final SkyEvent e;
  @override
  Widget build(BuildContext context) => GlassCard(
        onTap: () => showLookSheet(context, e),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            EventGlyph.of(e),
            const Spacer(),
            CloudPill(e.cloudCoverPercent),
          ]),
          const SizedBox(height: 14),
          Text(eventTitle(e), style: display(19, weight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(eventSubtitle(e), style: const TextStyle(color: LookUpColors.grey, fontSize: 14, height: 1.4)),
        ]),
      );
}

/// Nothing alert-worthy in the next 7 nights. Says when the next pass is,
/// why the sky goes quiet, and offers the preview.
class _QuietCard extends ConsumerWidget {
  const _QuietCard({this.nextBeyond});
  final SkyEvent? nextBeyond;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final n = nextBeyond;
    return GlassCard(
      tint: LookUpColors.blue,
      onTap: n == null ? null : () => showLookSheet(context, n),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Kicker('This week'),
          const SizedBox(height: 8),
          Text('A quiet sky', style: display(32, weight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text(
            'The space station is only visible near dawn and dusk, when you\'re in the dark and it\'s still in sunlight. '
            'Those windows come and go in cycles of a couple of weeks, and this is an off week here.',
            style: t.bodyMedium?.copyWith(color: LookUpColors.grey),
          ),
          if (n != null) ...[
            const SizedBox(height: 18),
            const Divider(),
            const SizedBox(height: 16),
            Row(children: [
              EventGlyph.of(n),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Kicker('Next visible pass', color: LookUpColors.blue),
                  const SizedBox(height: 2),
                  Text('${fmtDay(n.start)}, ${fmtTime(n.start)}', style: display(20, weight: FontWeight.w600)),
                ]),
              ),
            ]),
            const SizedBox(height: 10),
            Text(eventSubtitle(n), style: t.bodyMedium?.copyWith(color: LookUpColors.grey)),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => showDemo(context, ref),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Preview an alert'),
          ),
        ],
      ),
    );
  }
}

class _OfflineCard extends StatelessWidget {
  const _OfflineCard({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => GlassCard(
        tint: LookUpColors.warn,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: EventGlyph(icon: Icons.cloud_off_rounded, color: LookUpColors.warn, size: 40),
          ),
          const SizedBox(height: 16),
          Text('Couldn\'t reach the sky', style: display(26, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('LookUp needs a connection once to download orbits. After that it works offline for days.',
              style: TextStyle(color: LookUpColors.grey, height: 1.45)),
          const SizedBox(height: 18),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ]),
      );
}

/// Location refused and no place pinned: say why we need it, offer both ways.
class _LocationCard extends ConsumerWidget {
  const _LocationCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) => GlassCard(
        tint: LookUpColors.blue,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: EventGlyph(icon: Icons.near_me_rounded, color: LookUpColors.blue, size: 40),
          ),
          const SizedBox(height: 16),
          Text('Where\'s your sky?', style: display(28, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text(
            'Everything overhead depends on where you stand. LookUp needs a rough location, a town is plenty, '
            'and it never leaves your phone.',
            style: TextStyle(color: LookUpColors.grey, height: 1.45),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () async {
              final loc = ref.read(locationServiceProvider);
              final access = await loc.access();
              if (access == LocationAccess.blocked || access == LocationAccess.servicesOff) {
                await loc.openSettings();
              } else {
                await ref.read(homeProvider.notifier).refresh(force: true);
              }
            },
            icon: const Icon(Icons.my_location_rounded),
            label: const Text('Use my location'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => openPlaces(context),
            icon: const Icon(Icons.search_rounded),
            label: const Text('Choose a place instead'),
          ),
        ]),
      );
}

/// Notifications are switched off: the one thing that breaks the product.
class _AlertsOffCard extends ConsumerWidget {
  const _AlertsOffCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) => GlassCard(
        tint: LookUpColors.warn,
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(children: [
          const EventGlyph(icon: Icons.notifications_off_rounded, color: LookUpColors.warn),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Alerts are off, so LookUp can\'t tap you when something\'s up.', style: TextStyle(fontSize: 14, height: 1.35)),
          ),
          TextButton(
            onPressed: () async {
              final ok = await ref.read(notificationServiceProvider).requestPermission();
              if (!ok) await ref.read(locationServiceProvider).openSettings();
              ref.invalidate(alertsEnabledProvider);
            },
            child: const Text('Turn on'),
          ),
        ]),
      );
}

/// Tonight's clouds and what's up at a glance. Opens the Sky tab.
/// Everything else worth a look tonight, one row each, so the screen stays
/// about the next thing to see.
class _MoreTonight extends ConsumerWidget {
  const _MoreTonight();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionHeader('More tonight'),
        Rise(
          index: 3,
          child: GroupedList(indent: 64, children: [
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
            () {
              final (line, go) = _whereLine(ref);
              return ListRow(
                leading: const EventGlyph(icon: Icons.near_me_rounded, color: LookUpColors.violet),
                title: 'Where to go tonight',
                subtitle: line,
                subtitleLines: 1,
                trailing: go ? const Pill('Clearer', dot: true, color: LookUpColors.violet) : null,
                chevron: true,
                onTap: () => openWhereToGo(context),
              );
            }(),
          ]),
        ),
      ]);

  /// "Saturn tonight", "Saturn, Thursday", or how to start.
  static String _favouritesLine(WidgetRef ref) {
    final favourites = ref.watch(favouritesAheadProvider).value ?? const <FavouriteOutlook>[];
    if (favourites.isEmpty) return 'Tap \u2665 on anything in the Sky tab to follow it';
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

  /// The recommendation's headline, a darker sky nearby, or what it does.
  static (String, bool) _whereLine(WidgetRef ref) {
    final w = ref.watch(whereToGoProvider).value;
    if (w != null && w.result.kind != WhereToGoKind.noForecast) {
      return (whereToGoWords(w.result).headline, w.result.kind == WhereToGoKind.go);
    }
    if (w == null) {
      final d = ref.watch(darkSpotsProvider).value;
      final spot = d?.spots.where((s) => darknessForSqm(s.sqm) == SkyDarkness.dark).firstOrNull;
      if (spot != null && (d!.here == null || darknessForSqm(d.here!) != SkyDarkness.dark)) {
        return ('A dark sky ${spotName(spot)}', false);
      }
    }
    return ('Compare clouds at your places, find darker skies', false);
  }
}
