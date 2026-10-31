import 'package:flutter/material.dart' hide Badge;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_store.dart';
import '../domain/log/sighting.dart';
import '../domain/log/sky_log.dart';
import '../domain/models/sky_event.dart';
import '../services/photo_store.dart';
import '../state/providers.dart';
import 'format.dart';
import 'kit/kit.dart';
import 'theme.dart';
import 'year_card.dart';

/// Your sky log: what you've seen and the badges you've earned.
class LogScreen extends ConsumerStatefulWidget {
  const LogScreen({super.key});

  @override
  ConsumerState<LogScreen> createState() => _LogScreenState();

  static String _typeLabel(SkyEventType? t) => _LogScreenState._typeLabel(t);
}

class _LogScreenState extends ConsumerState<LogScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final log = ref.watch(skyLogProvider);
    final top = MediaQuery.paddingOf(context).top + AppHeader.height;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const AppHeader(title: Text('Sky log')),
      body: SkyBackdrop(
        stars: false,
        glow: LookUpColors.violet,
        child: log.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (l) => ListView(
            padding: EdgeInsets.fromLTRB(16, top + 14, 16, tabBarClearance(context)),
            children: [
              Rise(
                index: 0,
                child: GlassCard(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: IntrinsicHeight(
                    child: Row(children: [
                      Expanded(child: StatTile(k: 'Seen', v: '${l.total}', align: CrossAxisAlignment.center)),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: StatTile(k: 'Badges', v: '${l.earnedCount}/${l.badges.length}', align: CrossAxisAlignment.center),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: StatTile(
                          k: 'Hit rate',
                          v: l.hitRate == null ? '–' : '${(l.hitRate! * 100).round()}%',
                          align: CrossAxisAlignment.center,
                          valueColor: LookUpColors.blue,
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
              ..._yearCard(context, ref),
              if (l.total == 0)
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 20, 4, 0),
                  child: Text(
                    'Nothing logged yet. After each event LookUp asks "Did you see it?". Every yes lands here.',
                    style: TextStyle(color: LookUpColors.grey, height: 1.45),
                  ),
                ),
              const SizedBox(height: 24),
              SegmentedTabs(
                labels: const ['Seen', 'Badges'],
                counts: [l.total, l.earnedCount],
                index: _tab,
                onSelect: (i) => setState(() => _tab = i),
              ),
              const SizedBox(height: 12),
              if (_tab == 0 && l.seen.isNotEmpty)
                GroupedList(indent: 68, children: [
                  for (final s in l.seen.take(50))
                    ListRow(
                      onTap: () => _showSighting(context, ref, s),
                      leading: _Thumb(s.photo, type: s.inferredType),
                      title: _typeLabel(s.inferredType),
                      subtitle: [
                        fmtDay(s.eventTime ?? s.at),
                        if (s.place != null && s.place!.isNotEmpty) s.place!,
                      ].join(' · '),
                      subtitleLines: 1,
                    ),
                ])
              else if (_tab == 1)
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.78,
                  children: [for (final (i, b) in l.badges.indexed) Rise(index: i, child: _BadgeTile(b))],
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _yearCard(BuildContext context, WidgetRef ref) {
    final r = ref.watch(yearReviewProvider).value;
    if (r == null) return const [];
    return [
      const SizedBox(height: 12),
      Rise(
        index: 1,
        child: GlassCard(
          tint: LookUpColors.violet,
          onTap: () => showYearCard(context, r),
          padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Kicker('Your ${r.year} in the sky', color: LookUpColors.violet),
                const SizedBox(height: 4),
                Text('${r.seen} seen over ${r.nights} night${r.nights == 1 ? '' : 's'} out', style: display(19, weight: FontWeight.w600)),
              ]),
            ),
            CircleButton(icon: Icons.ios_share_rounded, tooltip: 'Share your year', onPressed: () => showYearCard(context, r)),
          ]),
        ),
      ),
    ];
  }

  static Future<void> _showSighting(BuildContext context, WidgetRef ref, Sighting s) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => _SightingSheet(s),
      );

  static String _typeLabel(SkyEventType? t) => switch (t) {
        SkyEventType.iss => 'Space station',
        SkyEventType.tiangong => 'Tiangong',
        SkyEventType.starlinkTrain => 'Starlink train',
        SkyEventType.auroraNow || SkyEventType.auroraOutlook => 'Aurora',
        SkyEventType.meteorShower => 'Meteor shower',
        SkyEventType.lunarEclipse => 'Lunar eclipse',
        SkyEventType.solarEclipse => 'Solar eclipse',
        SkyEventType.planetPairing => 'Planet pairing',
        SkyEventType.rocketLaunch => 'Rocket launch',
        SkyEventType.issTransit => 'Station transit',
        SkyEventType.satellitePass => 'Satellite',
        SkyEventType.planetHighlight => 'Planet',
        SkyEventType.skyObject => 'Sky object',
        null => 'Sky event',
      };
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile(this.b);
  final Badge b;
  @override
  Widget build(BuildContext context) {
    final earned = b.earned;
    return Semantics(
      label: '${b.title}${earned ? ', earned' : ', not yet earned'}. ${b.description}',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: LookUpColors.glass,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: earned ? LookUpColors.gold.withValues(alpha: 0.35) : LookUpColors.line),
        ),
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
        child: Column(children: [
          EventGlyph(
            icon: earned ? Icons.workspace_premium_rounded : Icons.lock_outline_rounded,
            color: earned ? LookUpColors.gold : LookUpColors.greyDim,
            size: 40,
          ),
          const SizedBox(height: 10),
          Text(b.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  letterSpacing: -0.2,
                  color: earned ? LookUpColors.white : LookUpColors.grey)),
          const SizedBox(height: 4),
          Expanded(
            child: Text(b.description,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, height: 1.3, color: LookUpColors.greyDim)),
          ),
        ]),
      ),
    );
  }
}

/// A small square of the sighting's photo, or nothing.
class _Thumb extends StatelessWidget {
  const _Thumb(this.name, {this.type});
  final String? name;
  final SkyEventType? type;
  @override
  Widget build(BuildContext context) {
    if (name == null) return EventGlyph.forType(type, size: 40);
    return FutureBuilder(
      future: const PhotoStore().fileFor(name),
      builder: (context, snap) => ClipRRect(
        borderRadius: BorderRadius.circular(Radii.sm),
        child: SizedBox(
          width: 40,
          height: 40,
          child: snap.data == null
              ? const ColoredBox(color: LookUpColors.panelRaised)
              : Image.file(snap.data!, fit: BoxFit.cover, cacheWidth: 120),
        ),
      ),
    );
  }
}

/// One sighting: the photo (or a button to add one) and the details.
class _SightingSheet extends ConsumerStatefulWidget {
  const _SightingSheet(this.s);
  final Sighting s;
  @override
  ConsumerState<_SightingSheet> createState() => _SightingSheetState();
}

class _SightingSheetState extends ConsumerState<_SightingSheet> {
  late String? _photo = widget.s.photo;

  Future<void> _pick() async {
    try {
      final name = await const PhotoStore().pickFor(widget.s.eventId);
      if (name == null) return;
      final old = _photo;
      await ref.read(storeProvider).setPhoto(widget.s.eventId, name);
      if (old != null) await const PhotoStore().delete(old);
      ref.invalidate(skyLogProvider);
      if (mounted) setState(() => _photo = name);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Couldn\'t open your photos. Check Photos access in Settings.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            EventGlyph.forType(s.inferredType, size: 40),
            const SizedBox(width: 12),
            Expanded(child: Text(LogScreen._typeLabel(s.inferredType), style: display(26, weight: FontWeight.w700))),
          ]),
          const SizedBox(height: 10),
          Text([
            fmtDay(s.eventTime ?? s.at),
            fmtTime(s.eventTime ?? s.at),
            if (s.place != null && s.place!.isNotEmpty) s.place!,
          ].join(' · '), style: numeric(size: 14, color: LookUpColors.grey)),
          const SizedBox(height: 16),
          if (_photo != null)
            FutureBuilder(
              future: const PhotoStore().fileFor(_photo),
              builder: (context, snap) => snap.data == null
                  ? const SizedBox(height: 200)
                  : ClipRRect(borderRadius: BorderRadius.circular(Radii.lg), child: Image.file(snap.data!, fit: BoxFit.cover)),
            ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _pick,
            icon: const Icon(Icons.add_a_photo_rounded),
            label: Text(_photo == null ? 'Add your photo' : 'Replace photo'),
          ),
        ]),
      ),
    );
  }
}
