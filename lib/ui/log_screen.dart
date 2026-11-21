import 'package:material_ui/material_ui.dart' hide Badge;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_store.dart';
import '../domain/log/sighting.dart';
import '../domain/models/sky_event.dart';
import '../services/photo_store.dart';
import '../state/providers.dart';
import 'format.dart';
import 'badges/badge_board.dart';
import 'keep_catch.dart';
import 'kit/kit.dart';
import 'settings_screen.dart';
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
      appBar: const AppHeader(title: Text('Sky log'), actions: [SettingsButton()]),
      body: SkyBackdrop(
        stars: false,
        glow: LookUpColors.violet,
        child: log.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => LoadTrouble(what: 'Your Log didn\'t load.', onRetry: () => ref.invalidate(skyLogProvider)),
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
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(
                      'Nothing caught yet. Tap Pip, follow it to something in the sky, and tap Pip again to catch it. Every catch lands here.',
                      style: TextStyle(color: LookUpColors.grey, height: 1.45),
                    ),
                    SizedBox(height: 12),
                    Text('New phone? Your catches are still in your LookUp album.', style: TextStyle(color: LookUpColors.grey, fontSize: 13.5)),
                    SizedBox(height: 8),
                    BringBackCatches(),
                  ]),
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
                      leading: _Thumb(s.photo, asset: s.photoAsset, type: s.inferredType),
                      title: _typeLabel(s.inferredType),
                      subtitle: [
                        fmtDay(s.eventTime ?? s.at),
                        if (s.place != null && s.place!.isNotEmpty) s.place!,
                      ].join(' · '),
                      subtitleLines: 1,
                    ),
                ])
              else if (_tab == 1)
                BadgeBoard(log: l),
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
        SkyEventType.iss => 'ISS',
        SkyEventType.tiangong => 'Tiangong',
        SkyEventType.starlinkTrain => 'Starlink train',
        SkyEventType.auroraNow || SkyEventType.auroraOutlook => 'Aurora',
        SkyEventType.meteorShower => 'Meteor shower',
        SkyEventType.lunarEclipse => 'Lunar eclipse',
        SkyEventType.fullMoonRise => 'Full Moon',
        SkyEventType.solarEclipse => 'Solar eclipse',
        SkyEventType.planetPairing => 'Planet pairing',
        SkyEventType.occultation || SkyEventType.occultationNear => 'Occultation',
        SkyEventType.rocketLaunch => 'Rocket launch',
        SkyEventType.issTransit => 'Station transit',
        SkyEventType.satellitePass => 'Satellite',
        SkyEventType.planetHighlight => 'Planet',
        SkyEventType.skyObject => 'Sky object',
        SkyEventType.comet => 'Comet',
        SkyEventType.nova => 'Nova',
        null => 'Sky event',
      };
}

/// A small square of the sighting's photo, or nothing.
class _Thumb extends StatelessWidget {
  const _Thumb(this.name, {this.asset, this.type});
  final String? name, asset;
  final SkyEventType? type;
  @override
  Widget build(BuildContext context) {
    if (name == null && asset == null) return EventGlyph.forType(type, size: 40);
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.sm),
      child: SizedBox(width: 40, height: 40, child: SightingPicture(photo: name, asset: asset)),
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
  late String? _asset = widget.s.photoAsset;

  Future<void> _pick() async {
    try {
      final name = await const PhotoStore().pickFor(widget.s.eventId);
      if (name == null) return;
      final old = _photo;
      await ref.read(storeProvider).setPhoto(widget.s.eventId, name);
      if (old != null) await const PhotoStore().delete(old);
      ref.invalidate(skyLogProvider);
      if (mounted) {
        setState(() {
          _photo = name;
          _asset = null;
        });
      }
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
          if (_photo != null || _asset != null) SightingPicture(photo: _photo, asset: _asset, large: true),
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
