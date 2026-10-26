import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/sky_event.dart';
import '../domain/sky/astro.dart' show PlanetInfo;
import '../services/location_service.dart';
import '../state/providers.dart';
import '../state/sky_state.dart';
import 'demo.dart';
import 'finder_screen.dart';
import 'widgets/pass_timeline.dart';
import 'fancy/foil_text.dart';
import 'fancy/invite_frame.dart';
import 'fancy/ornament_rule.dart';
import 'fancy/rise.dart';
import 'fancy/starfield.dart';
import 'fancy/woven.dart';
import 'format.dart';
import 'look_sheet.dart';
import 'paywall_sheet.dart';
import 'settings_screen.dart';
import 'sky/night_strip.dart';
import 'sky/sky_thing.dart';
import 'places_screen.dart';
import 'theme.dart';

class NowScreen extends ConsumerWidget {
  const NowScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(homeProvider);
    final settings = ref.watch(settingsProvider).value;
    final place = (settings?.placeName?.isNotEmpty ?? false) ? settings!.placeName! : 'Near you';
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: WovenHeader(
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('LookUp'),
          Text('.', style: displaySerif(context, size: 21, weight: FontWeight.w700, color: LookUpColors.blue)),
        ]),
        subtitle: place,
        onSubtitleTap: () => openPlaces(context),
        trailing: IconButton(
          tooltip: 'Settings',
          icon: const Icon(Icons.settings_outlined, size: 21, color: LookUpColors.grey),
          onPressed: () => openSettings(context),
        ),
      ),
      body: Starfield(
        child: RefreshIndicator(
          edgeOffset: MediaQuery.paddingOf(context).top + 58,
          onRefresh: () => ref.read(homeProvider.notifier).refresh(force: true),
          child: home.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text('$e'))]),
            data: (d) => ListView(
              padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 58 + 16, 16, 32),
              children: [
                if (ref.watch(alertsEnabledProvider).value == false && !d.needsLocation)
                  const Padding(padding: EdgeInsets.only(bottom: 14), child: _AlertsOffCard()),
                Rise(
                  index: 0,
                  child: d.needsLocation
                      ? const _LocationCard()
                      : d.noData
                          ? _OfflineCard(onRetry: () => ref.read(homeProvider.notifier).refresh(force: true))
                          : (d.next == null || d.next!.details['lookahead'] == true)
                              ? _QuietCard(nextBeyond: d.next)
                              : _NextCard(event: d.next!),
                ),
                if (d.auroraOutlook != null) ...[
                  const SizedBox(height: 14),
                  Rise(index: 1, child: _OutlookCard(d.auroraOutlook!)),
                ],
                if (!d.needsLocation) const Padding(padding: EdgeInsets.only(top: 14), child: Rise(index: 2, child: _TonightSkyCard())),
                if (d.next?.details['lookahead'] != true) ..._later(context, ref, d),
                if (d.errors.isNotEmpty && !d.needsLocation)
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Text('Couldn\'t refresh everything. Showing the last good copy.',
                        textAlign: TextAlign.center, style: const TextStyle(color: LookUpColors.greyDim, fontSize: 12)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The next two things after the hero, as quiet rows, and a way to the week.
  List<Widget> _later(BuildContext context, WidgetRef ref, HomeData d) {
    final rest = d.events.where((e) => e.id != d.next?.id && e.type.pushes).take(2).toList();
    if (rest.isEmpty) return const [];
    return [
      const Padding(
        padding: EdgeInsets.fromLTRB(4, 28, 4, 4),
        child: OrnamentRule(label: 'Later'),
      ),
      Rise(
        index: 2,
        child: WovenRows(padding: const EdgeInsets.symmetric(horizontal: 4), children: [for (final e in rest) _SmallRow(e)]),
      ),
      Align(
        child: TextButton(
          onPressed: () => ref.read(homeTabProvider.notifier).set(2),
          child: const Text('See the whole week'),
        ),
      ),
    ];
  }
}

class _NextCard extends ConsumerStatefulWidget {
  const _NextCard({required this.event});
  final SkyEvent event;
  @override
  ConsumerState<_NextCard> createState() => _NextCardState();
}

class _NextCardState extends ConsumerState<_NextCard> {
  bool? _wasLive;

  SkyEvent get event => widget.event;

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final t = Theme.of(context).textTheme;
    final live = !now.toUtc().isBefore(event.start);
    final until = event.start.difference(now.toUtc());
    // Go-now moment while the app is open: a firm buzz and a chime.
    if (_wasLive == false && live) {
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
      ref.read(liveActivityProvider).markLive();
    }
    _wasLive = live;
    final isPass = event.type == SkyEventType.iss || event.type == SkyEventType.tiangong || event.type == SkyEventType.starlinkTrain;
    return InviteFrame(
      onTap: () => showLookSheet(context, event),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Eyebrow(live ? 'Happening now' : 'Next up', color: live ? LookUpColors.blue : LookUpColors.grey),
                const Spacer(),
                _CloudChip(event.cloudCoverPercent),
              ]),
              const SizedBox(height: 14),
              Text(eventTitle(event), style: displaySerif(context, size: 40, weight: FontWeight.w500)),
              const SizedBox(height: 2),
              Semantics(
                liveRegion: true,
                label: live ? 'Happening now. Go outside.' : 'Starts in ${fmtCountdown(until)}',
                child: FoilText(
                  live ? 'Go outside now' : 'in ${fmtCountdown(until)}',
                  style: displaySerif(context, size: 58, weight: FontWeight.w600, italic: true, height: 1.0),
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Text(fmtDay(event.start).toUpperCase(),
                    style: t.labelSmall?.copyWith(color: LookUpColors.grey, letterSpacing: 2, fontWeight: FontWeight.w700)),
                const SizedBox(width: 10),
                Container(width: 1, height: 10, color: LookUpColors.line),
                const SizedBox(width: 10),
                Text(fmtTime(event.start), style: monoData(context, size: 13, color: LookUpColors.grey)),
              ]),
              const SizedBox(height: 16),
              Container(height: 1, color: LookUpColors.line),
              const SizedBox(height: 14),
              Text(eventSubtitle(event), style: t.bodyLarge?.copyWith(height: 1.4)),
              if (live && isPass) ...[
                const SizedBox(height: 16),
                PassTimeline(event: event, now: now),
              ],
              if (live || until < const Duration(minutes: 30)) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => openFinder(context, event),
                  icon: const Icon(Icons.explore_outlined),
                  label: const Text('FIND IT IN THE SKY'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ],
              if (event.isEstimate)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Estimate — orbit data is a few days old', style: t.bodySmall?.copyWith(color: LookUpColors.warn)),
                ),
              if (event.plusOnly && !(ref.watch(settingsProvider).value?.isPlus ?? false))
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: GestureDetector(
                    onTap: () => showPaywall(context, reason: event),
                    child: Row(children: [
                      const Eyebrow('LookUp+ taps you 10 min before', color: LookUpColors.blue),
                      const Spacer(),
                      Icon(Icons.arrow_forward, size: 16, color: LookUpColors.blue),
                    ]),
                  ),
                ),
            ],
          ),
    );
  }
}

class _OutlookCard extends StatelessWidget {
  const _OutlookCard(this.e);
  final SkyEvent e;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(eventTitle(e), style: displaySerif(context, size: 24, weight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(eventSubtitle(e), style: const TextStyle(color: LookUpColors.grey, fontSize: 13)),
              ]),
            ),
            const SizedBox(width: 12),
            _CloudChip(e.cloudCoverPercent),
          ]),
        ),
      );
}

class _SmallRow extends StatelessWidget {
  const _SmallRow(this.e);
  final SkyEvent e;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => showLookSheet(context, e),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(eventTitle(e), style: displaySerif(context, size: 22, weight: FontWeight.w500)),
                const SizedBox(height: 3),
                Text('${fmtDay(e.start)}, ${fmtTime(e.start)}',
                    style: const TextStyle(color: LookUpColors.grey, fontSize: 13)),
              ]),
            ),
            const SizedBox(width: 12),
            _CloudChip(e.cloudCoverPercent),
          ]),
        ),
      );
}

class _CloudChip extends StatelessWidget {
  const _CloudChip(this.cover);
  final int? cover;
  @override
  Widget build(BuildContext context) {
    final icon = cover == null
        ? Icons.help_outline
        : cover! <= 20
            ? Icons.nightlight_round
            : cover! <= 60
                ? Icons.cloud_queue
                : Icons.cloud;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 15, color: LookUpColors.grey),
      const SizedBox(width: 5),
      Text(cloudWord(cover).toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: LookUpColors.grey, fontSize: 10.5, letterSpacing: 1.5, fontWeight: FontWeight.w600)),
    ]);
  }
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
    return InviteFrame(
      onTap: n == null ? null : () => showLookSheet(context, n),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('This week'),
          const SizedBox(height: 14),
          Text('A quiet sky', style: displaySerif(context, size: 40, weight: FontWeight.w500)),
          const SizedBox(height: 10),
          Text(
            'The space station is only visible near dawn and dusk, when you\'re in the dark and it\'s still in sunlight. '
            'Those windows come and go in cycles of a couple of weeks, and this is an off week here.',
            style: t.bodyMedium?.copyWith(color: LookUpColors.grey, height: 1.45),
          ),
          if (n != null) ...[
            const SizedBox(height: 16),
            Container(height: 1, color: LookUpColors.line),
            const SizedBox(height: 14),
            const Eyebrow('Next visible pass', color: LookUpColors.blue),
            const SizedBox(height: 6),
            FoilText(
              '${fmtDay(n.start)}, ${fmtTime(n.start)}',
              style: displaySerif(context, size: 34, weight: FontWeight.w600, italic: true, height: 1.05),
            ),
            const SizedBox(height: 6),
            Text(eventSubtitle(n), style: t.bodyMedium?.copyWith(height: 1.4)),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => showDemo(context, ref),
            icon: const Icon(Icons.play_arrow),
            label: const Text('PREVIEW AN ALERT'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
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
  Widget build(BuildContext context) => InviteFrame(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Eyebrow('No signal', color: LookUpColors.warn),
          const SizedBox(height: 14),
          Text('Couldn\'t reach the sky', style: displaySerif(context, size: 36, weight: FontWeight.w500)),
          const SizedBox(height: 10),
          const Text('LookUp needs a connection once to download orbits. After that it works offline for days.',
              style: TextStyle(color: LookUpColors.grey, height: 1.45)),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('TRY AGAIN')),
        ]),
      );
}

/// Location refused and no place pinned: say why we need it, offer both ways.
class _LocationCard extends ConsumerWidget {
  const _LocationCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) => InviteFrame(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Eyebrow('One thing first', color: LookUpColors.blue),
          const SizedBox(height: 14),
          Text('Where\'s your sky?', style: displaySerif(context, size: 36, weight: FontWeight.w500)),
          const SizedBox(height: 10),
          const Text(
            'Everything overhead depends on where you stand. LookUp needs a rough location, a town is plenty, '
            'and it never leaves your phone.',
            style: TextStyle(color: LookUpColors.grey, height: 1.45),
          ),
          const SizedBox(height: 16),
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
            icon: const Icon(Icons.my_location),
            label: const Text('USE MY LOCATION'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => openPlaces(context),
            icon: const Icon(Icons.search),
            label: const Text('CHOOSE A PLACE INSTEAD'),
          ),
        ]),
      );
}

/// Notifications are switched off: the one thing that breaks the product.
class _AlertsOffCard extends ConsumerWidget {
  const _AlertsOffCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: Color(0x66E6B450)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
          child: Row(children: [
            const Icon(Icons.notifications_off_outlined, color: LookUpColors.warn),
            const SizedBox(width: 14),
            const Expanded(
              child: Text('Alerts are off, so LookUp can\'t tap you when something\'s up.',
                  style: TextStyle(height: 1.35)),
            ),
            TextButton(
              onPressed: () async {
                final ok = await ref.read(notificationServiceProvider).requestPermission();
                if (!ok) await ref.read(locationServiceProvider).openSettings();
                ref.invalidate(alertsEnabledProvider);
              },
              child: const Text('TURN ON'),
            ),
          ]),
        ),
      );
}

/// Tonight's clouds and what's up, in four lines. Opens the Sky tab.
class _TonightSkyCard extends ConsumerWidget {
  const _TonightSkyCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tonightSkyProvider).value;
    if (t == null) return const SizedBox.shrink();
    final up = [
      for (final p in t.visiblePlanets) p.planet.label,
      if (t.moon.sighting?.verdict.yes ?? false) 'the Moon (${(t.moon.illumination * 100).round()}%)',
    ];
    return Card(
      child: InkWell(
        onTap: () => ref.read(homeTabProvider.notifier).set(1),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 14, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Eyebrow('Tonight\'s sky'),
              const Spacer(),
              const Text('Explore', style: TextStyle(color: LookUpColors.blue, fontSize: 13, fontWeight: FontWeight.w600)),
              const Icon(Icons.chevron_right, size: 18, color: LookUpColors.blue),
            ]),
            const SizedBox(height: 10),
            if (t.outlook != null) ...[
              Text(outlookWords(t.outlook!), style: displaySerif(context, size: 24, weight: FontWeight.w500)),
              const SizedBox(height: 10),
              if (t.outlook!.hasForecast) NightStrip(outlook: t.outlook!, compact: true),
              const SizedBox(height: 12),
            ],
            Text(
              up.isEmpty ? 'No bright planets up tonight.' : 'Up tonight: ${up.join(', ')}.',
              style: const TextStyle(color: LookUpColors.grey, height: 1.4),
            ),
          ]),
        ),
      ),
    );
  }
}
