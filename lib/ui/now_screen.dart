import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/aurora_reports_client.dart' show relayConfigured;
import '../domain/aurora/seen_nearby.dart' show seenNearYouLine;
import '../domain/models/sky_event.dart';
import '../services/location_service.dart';
import '../state/providers.dart';
import 'demo.dart';
import 'format.dart';
import 'kit/kit.dart';
import 'look_sheet.dart';
import 'places_screen.dart';
import 'settings_screen.dart';
import 'soft_asks.dart';
import 'theme.dart';
import 'tour.dart';
import 'verdict_card.dart';

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
          KeyedSubtree(
            key: TourKeys.settings,
            child: const SettingsButton(),
          ),
        ],
      ),
      body: SkyBackdrop(
        glow: next == null ? LookUpColors.blue : eventStyle(next.type, details: next.details).color,
        child: RefreshIndicator(
          edgeOffset: top,
          onRefresh: () => ref.read(homeProvider.notifier).pull(),
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
                if (!d.needsLocation && !d.noData) ..._comingUp(context, ref, d),
                // At most one soft LookUp+ ask, by the shared budget; usually nothing.
                if (!d.needsLocation && !d.noData) HomeAsk(home: d),
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

  /// The next three things after the hero, soonest first, each in one
  /// line. Rows that won't be worth stepping out for (cloud, no alert) fade
  /// back; everything else is a tap away in "See every night".
  List<Widget> _comingUp(BuildContext context, WidgetRef ref, HomeData d) {
    final now = DateTime.now().toUtc();
    final horizon = now.add(const Duration(days: 7));
    final seen = seenNearYouLine(d.events, DateTime.now(), relayConfigured: relayConfigured);
    final outlook = seen == null ? d.auroraOutlook : null;
    // The outlook has its own row at the top; don't list it twice.
    final rest = d.events
        .where((e) => e.id != d.next?.id && e.id != outlook?.id && e.end.isAfter(now) && e.start.isBefore(horizon))
        .take(3)
        .toList();
    return [
      const SectionHeader('Coming up'),
      Rise(
        index: 3,
        child: GroupedList(indent: 64, children: [
          if (seen != null) _row(context, seen, kicker: 'Seen near you'),
          if (outlook != null && outlook.id != d.next?.id) _row(context, outlook),
          for (final e in rest) _row(context, e),
          if (rest.isEmpty && seen == null && outlook == null)
            const ListRow(
              leading: EventGlyph(icon: Icons.bedtime_rounded, color: LookUpColors.greyDim),
              title: 'Nothing else this week',
              subtitle: 'LookUp keeps watching and taps you when that changes',
            ),
          ListRow(
            leading: const EventGlyph(icon: Icons.view_agenda_rounded, color: LookUpColors.blue),
            title: 'See every night',
            subtitle: 'What\'s coming, and what went by',
            subtitleLines: 1,
            chevron: true,
            onTap: () => ref.read(homeTabProvider.notifier).set(HomeTab.week),
          ),
        ]),
      ),
    ];
  }

  Widget _row(BuildContext context, SkyEvent e, {String? kicker}) {
    final quiet = !e.type.pushes;
    final cloudy = (e.cloudCoverPercent ?? 0) >= 80;
    return Opacity(
      opacity: quiet || cloudy ? 0.6 : 1,
      // Day and time on one line under the name; cloud as a small icon, not
      // a pill, so nothing crowds the right-hand edge.
      child: ListRow(
        leading: EventGlyph.of(e, dim: quiet || cloudy),
        title: kicker ?? eventTitle(e),
        subtitle: kicker != null
            ? eventTitle(e)
            : '${fmtDay(e.start)}, ${fmtTime(e.start)}${quiet ? ' · No alert' : cloudy ? ' · Cloudy' : ''}',
        subtitleLines: 1,
        trailing: cloudy && !quiet ? const Icon(Icons.cloud_rounded, size: 18, color: LookUpColors.greyDim) : null,
        chevron: true,
        onTap: () => showLookSheet(context, e),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();
  @override
  Widget build(BuildContext context) =>
      Text.rich(TextSpan(text: 'LookUp', children: [TextSpan(text: '.', style: TextStyle(color: LookUpColors.blue))]));
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
