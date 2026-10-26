import 'package:flutter/material.dart' hide Badge;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_store.dart';
import '../domain/log/sighting.dart';
import '../domain/log/sky_log.dart';
import '../domain/models/sky_event.dart';
import '../services/photo_store.dart';
import '../state/providers.dart';
import 'fancy/foil_text.dart';
import 'fancy/rise.dart';
import 'fancy/stat_tile.dart';
import 'format.dart';
import 'fancy/woven.dart';
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
    return Scaffold(
      appBar: const WovenHeader(title: Text('Your sky log')),
      body: log.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (l) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Rise(
              index: 0,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    StatTile(k: 'Seen', v: '${l.total}'),
                    StatTile(k: 'Badges', v: '${l.earnedCount}/${l.badges.length}', align: CrossAxisAlignment.center),
                    StatTile(
                      k: 'Hit rate',
                      v: l.hitRate == null ? '–' : '${(l.hitRate! * 100).round()}%',
                      align: CrossAxisAlignment.end,
                      valueColor: LookUpColors.blue,
                    ),
                  ]),
                ),
              ),
            ),
            ..._yearCard(context, ref),
            if (l.total == 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 20, 4, 0),
                child: Text(
                  'Nothing logged yet. After each event LookUp asks "Did you see it?". Every yes lands here.',
                  style: const TextStyle(color: LookUpColors.grey, height: 1.45),
                ),
              ),
            const SizedBox(height: 18),
            WovenTabs(
              labels: const ['Seen', 'Badges'],
              counts: [l.total, l.earnedCount],
              index: _tab,
              onSelect: (i) => setState(() => _tab = i),
            ),
            const SizedBox(height: 8),
            if (_tab == 0)
              WovenRows(padding: EdgeInsets.zero, children: [
                for (final s in l.seen.take(50))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () => _showSighting(context, ref, s),
                    leading: _Thumb(s.photo),
                    title: Text(_typeLabel(s.inferredType), style: displaySerif(context, size: 21, weight: FontWeight.w500)),
                    subtitle: Text([
                      fmtDay(s.eventTime ?? s.at),
                      if (s.place != null && s.place!.isNotEmpty) s.place!,
                    ].join(' · ')),
                    trailing: const Icon(Icons.chevron_right, size: 18, color: LookUpColors.greyDim),
                  ),
              ])
            else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.82,
                  children: [for (final (i, b) in l.badges.indexed) Rise(index: i, child: _BadgeTile(b))],
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _yearCard(BuildContext context, WidgetRef ref) {
    final r = ref.watch(yearReviewProvider).value;
    if (r == null) return const [];
    return [
      const SizedBox(height: 10),
      Rise(
        index: 1,
        child: Card(
          child: InkWell(
            onTap: () => showYearCard(context, r),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Eyebrow('Your sky year · ${r.year}', color: LookUpColors.blue),
                    const SizedBox(height: 6),
                    Text('${r.seen} seen over ${r.nights} night${r.nights == 1 ? '' : 's'} out',
                        style: displaySerif(context, size: 22, weight: FontWeight.w500)),
                  ]),
                ),
                const Icon(Icons.ios_share, size: 20, color: LookUpColors.grey),
              ]),
            ),
          ),
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
        SkyEventType.planetPairing => 'Planet pairing',
        SkyEventType.rocketLaunch => 'Rocket launch',
        SkyEventType.issTransit => 'Station transit',
        SkyEventType.satellitePass => 'Satellite',
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
      child: Container(
        decoration: BoxDecoration(
          color: LookUpColors.panel,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: earned ? const Color(0x663C9DFF) : LookUpColors.line),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(earned ? Icons.auto_awesome : Icons.lock_outline,
              size: 26, color: earned ? LookUpColors.blue : LookUpColors.greyDim),
          const SizedBox(height: 8),
          earned
              ? FoilText(b.title, gold: true, textAlign: TextAlign.center, style: displaySerif(context, size: 17, weight: FontWeight.w600))
              : Text(b.title, textAlign: TextAlign.center, style: displaySerif(context, size: 17, weight: FontWeight.w500, color: LookUpColors.greyDim)),
          const SizedBox(height: 4),
          Text(b.description, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, height: 1.25, color: earned ? LookUpColors.grey : LookUpColors.greyDim)),
        ]),
      ),
    );
  }
}

/// A small square of the sighting's photo, or nothing.
class _Thumb extends StatelessWidget {
  const _Thumb(this.name);
  final String? name;
  @override
  Widget build(BuildContext context) {
    if (name == null) return const SizedBox(width: 44, child: Icon(Icons.auto_awesome, color: LookUpColors.greyDim, size: 20));
    return FutureBuilder(
      future: const PhotoStore().fileFor(name),
      builder: (context, snap) => ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 44,
          height: 44,
          child: snap.data == null ? const ColoredBox(color: LookUpColors.panelRaised) : Image.file(snap.data!, fit: BoxFit.cover, cacheWidth: 132),
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
          Text(LogScreen._typeLabel(s.inferredType), style: displaySerif(context, size: 32, weight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text([
            fmtDay(s.eventTime ?? s.at),
            fmtTime(s.eventTime ?? s.at),
            if (s.place != null && s.place!.isNotEmpty) s.place!,
          ].join(' · '), style: const TextStyle(color: LookUpColors.grey)),
          const SizedBox(height: 16),
          if (_photo != null)
            FutureBuilder(
              future: const PhotoStore().fileFor(_photo),
              builder: (context, snap) => snap.data == null
                  ? const SizedBox(height: 200)
                  : ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.file(snap.data!, fit: BoxFit.cover)),
            ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _pick,
            icon: const Icon(Icons.add_a_photo_outlined),
            label: Text(_photo == null ? 'Add your photo' : 'Replace photo'),
          ),
        ]),
      ),
    );
  }
}
