import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/settings.dart';
import '../domain/models/sky_event.dart';
import '../state/providers.dart';
import 'demo.dart';
import 'finder_screen.dart';
import 'widgets/pass_timeline.dart';
import 'fancy/foil_text.dart';
import 'fancy/invite_frame.dart';
import 'fancy/ornament_rule.dart';
import 'fancy/rise.dart';
import 'fancy/starfield.dart';
import 'format.dart';
import 'look_sheet.dart';
import 'paywall_sheet.dart';
import 'places_screen.dart';
import 'satellites_screen.dart';
import 'theme.dart';

class NowScreen extends ConsumerWidget {
  const NowScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(homeProvider);
    final settings = ref.watch(settingsProvider).value;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('LookUp', style: displaySerif(context, size: 26, weight: FontWeight.w600)),
          Text('.', style: displaySerif(context, size: 26, weight: FontWeight.w700, color: LookUpColors.blue)),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: TextButton.icon(
              onPressed: () => openPlaces(context),
              icon: Icon(settings?.locationMode == LocationMode.pinned ? Icons.place_outlined : Icons.near_me_outlined,
                  size: 16, color: LookUpColors.grey),
              label: Eyebrow((settings?.placeName?.isNotEmpty ?? false) ? settings!.placeName! : 'Here'),
            ),
          ),
        ],
      ),
      body: Starfield(
        child: RefreshIndicator(
        onRefresh: () => ref.read(homeProvider.notifier).refresh(force: true),
        child: home.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text('$e'))]),
          data: (d) => ListView(
            padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 64, 16, 32),
            children: [
              Rise(
                index: 0,
                child: d.noData
                    ? _OfflineCard(onRetry: () => ref.read(homeProvider.notifier).refresh(force: true))
                    : (d.next == null || d.next!.details['lookahead'] == true)
                        ? _QuietCard(nextBeyond: d.next)
                        : _NextCard(event: d.next!),
              ),
              const SizedBox(height: 14),
              if (d.auroraOutlook != null) Rise(index: 1, child: _OutlookCard(d.auroraOutlook!)),
              if (d.next?.details['lookahead'] != true) ..._then(d),
              ..._recent(d),
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: Wrap(alignment: WrapAlignment.center, spacing: 4, children: [
                  TextButton.icon(
                    onPressed: () => openSatellitesTonight(context),
                    icon: const Icon(Icons.satellite_alt_outlined, size: 18),
                    label: const Text('Satellites tonight'),
                  ),
                  TextButton.icon(
                    onPressed: () => showDemo(context, ref),
                    icon: const Icon(Icons.play_circle_outline, size: 18),
                    label: const Text('Preview an alert'),
                  ),
                ]),
              ),
              if (d.errors.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text('Some data didn\'t refresh: ${d.errors.length} source(s). Using the last good copy.',
                      style: const TextStyle(color: LookUpColors.greyDim, fontSize: 12)),
                ),
              if (d.lastRefresh != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Eyebrow('Updated ${fmtDay(d.lastRefresh!)} ${fmtTime(d.lastRefresh!)}', color: LookUpColors.greyDim),
                ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  List<Widget> _recent(HomeData d) {
    if (d.recent.isEmpty) return const [];
    return [
      const Padding(
        padding: EdgeInsets.fromLTRB(4, 26, 4, 14),
        child: OrnamentRule(label: 'Last 7 nights'),
      ),
      for (final (i, e) in d.recent.take(3).indexed) Rise(index: 4 + i, child: _PastRow(e)),
    ];
  }

  List<Widget> _then(HomeData d) {
    final rest = d.events
        .where((e) => e.id != d.next?.id && e.type.pushes)
        .take(2)
        .toList();
    if (rest.isEmpty) return const [];
    return [
      const Padding(
        padding: EdgeInsets.fromLTRB(4, 26, 4, 14),
        child: OrnamentRule(label: 'Then'),
      ),
      for (final (i, e) in rest.indexed) Rise(index: 2 + i, child: _SmallRow(e)),
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Card(
          child: InkWell(
            onTap: () => showLookSheet(context, e),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(eventTitle(e), style: displaySerif(context, size: 24, weight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(fmtDay(e.start).toUpperCase(),
                            style: const TextStyle(color: LookUpColors.grey, fontSize: 10.5, letterSpacing: 1.8, fontWeight: FontWeight.w700)),
                        Text('${fmtTime(e.start)} · ${e.peakElevationDeg.round()}°',
                            style: monoData(context, size: 12, color: LookUpColors.grey)),
                      ],
                    ),
                  ]),
                ),
                const SizedBox(width: 12),
                _CloudChip(e.cloudCoverPercent),
              ]),
            ),
          ),
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

/// Something that already happened over the user, with whether it was visible.
class _PastRow extends StatelessWidget {
  const _PastRow(this.e);
  final SkyEvent e;
  @override
  Widget build(BuildContext context) {
    final clouded = (e.cloudCoverPercent ?? 0) > 60;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: 0.82,
        child: Card(
          child: InkWell(
            onTap: () => showLookSheet(context, e),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(pastTitle(e), style: displaySerif(context, size: 22, weight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text(fmtDay(e.start).toUpperCase(),
                          style: const TextStyle(color: LookUpColors.grey, fontSize: 10.5, letterSpacing: 1.8, fontWeight: FontWeight.w700)),
                      Text(e.type == SkyEventType.auroraNow
                              ? 'Kp ${(e.details['kp'] as num?)?.toStringAsFixed(1)}'
                              : '${fmtTime(e.start)} · ${e.peakElevationDeg.round()}°',
                          style: monoData(context, size: 12, color: LookUpColors.grey)),
                    ]),
                  ]),
                ),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Icon(clouded ? Icons.cloud : Icons.visibility_outlined, size: 16,
                      color: clouded ? LookUpColors.greyDim : LookUpColors.blue),
                  const SizedBox(height: 4),
                  Text(clouded ? 'CLOUDED OUT' : 'VISIBLE',
                      style: TextStyle(
                          fontSize: 10, letterSpacing: 1.4, fontWeight: FontWeight.w700,
                          color: clouded ? LookUpColors.greyDim : LookUpColors.blue)),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
