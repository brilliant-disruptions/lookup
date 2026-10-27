import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/local_store.dart';
import '../domain/log/year_review.dart';
import '../domain/models/sky_event.dart';
import '../state/providers.dart';
import 'format.dart';
import 'kit/kit.dart';
import 'share_card.dart';
import 'theme.dart';

/// This calendar year's review, or null before the first sighting.
/// Rebuilds whenever the sky log does.
final yearReviewProvider = FutureProvider<YearReview?>((ref) async {
  await ref.watch(skyLogProvider.future);
  final f = await ref.read(storeProvider).loadFeedback();
  return YearReview.from([for (final x in f) x.toSighting()], DateTime.now().year,
      utcOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes);
});

String typePlural(SkyEventType t, int n) {
  final one = n == 1;
  return switch (t) {
    SkyEventType.iss => one ? 'space station pass' : 'space station passes',
    SkyEventType.tiangong => one ? 'Tiangong pass' : 'Tiangong passes',
    SkyEventType.starlinkTrain => one ? 'Starlink train' : 'Starlink trains',
    SkyEventType.auroraNow || SkyEventType.auroraOutlook => one ? 'aurora' : 'auroras',
    SkyEventType.meteorShower => one ? 'meteor shower' : 'meteor showers',
    SkyEventType.lunarEclipse => one ? 'lunar eclipse' : 'lunar eclipses',
    SkyEventType.planetPairing => one ? 'planet pairing' : 'planet pairings',
    SkyEventType.rocketLaunch => one ? 'rocket launch' : 'rocket launches',
    SkyEventType.issTransit => one ? 'station transit' : 'station transits',
    SkyEventType.satellitePass => one ? 'satellite' : 'satellites',
    SkyEventType.planetHighlight => one ? 'planet highlight' : 'planet highlights',
    SkyEventType.skyObject => one ? 'sky sight' : 'sky sights',
  };
}

String yearShareText(YearReview r) =>
    'My ${r.year} in the sky: ${r.seen} things seen over ${r.nights} nights out. Tracked with LookUp ✨';

Future<void> showYearCard(BuildContext context, YearReview r) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _YearSheet(r),
    );

class _YearSheet extends StatefulWidget {
  const _YearSheet(this.r);
  final YearReview r;
  @override
  State<_YearSheet> createState() => _YearSheetState();
}

class _YearSheetState extends State<_YearSheet> {
  final _key = GlobalKey();
  bool _busy = false;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: SizedBox(width: 300, child: RepaintBoundary(key: _key, child: YearCard(widget.r)))),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      try {
                        await sharePoster(_key, yearShareText(widget.r));
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              icon: const Icon(Icons.ios_share_rounded),
              label: const Text('Share your year'),
            ),
          ]),
        ),
      );
}

/// 4:5 poster, same family as the "I saw it" card.
class YearCard extends StatelessWidget {
  const YearCard(this.r, {super.key});
  final YearReview r;

  @override
  Widget build(BuildContext context) {
    final lines = <String>[
      for (final (t, n) in r.byType.take(3)) '$n ${typePlural(t, n)}',
      if (r.brightest?.magnitude != null) 'Brightest: magnitude ${r.brightest!.magnitude!.toStringAsFixed(1)}',
      if (r.highest?.peakElevationDeg != null) 'Highest pass: ${r.highest!.peakElevationDeg!.round()}° up',
      if (r.lateNights > 0) '${r.lateNights} after midnight',
    ];
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.lg),
        child: Container(
          decoration: posterDecoration(LookUpColors.violet),
          child: Starfield(
            density: 0.0008,
            maxOpacity: 0.6,
            seed: r.year,
            fadeBottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Kicker('My sky year', color: LookUpColors.violet),
                const SizedBox(height: 6),
                Text('${r.year}', style: display(64, weight: FontWeight.w800, height: 1)),
                const SizedBox(height: 8),
                Text('${r.seen} seen · ${r.nights} night${r.nights == 1 ? '' : 's'} out',
                    style: display(20, weight: FontWeight.w600)),
                const SizedBox(height: 14),
                for (final l in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(l, style: const TextStyle(color: LookUpColors.grey, fontSize: 13, height: 1.3)),
                  ),
                const Spacer(),
                if (r.bestMonth != null)
                  Text('Best month: ${DateFormat.MMMM().format(DateTime(r.year, r.bestMonth!))}',
                      style: numeric(size: 11.5, color: LookUpColors.grey)),
                if (r.first != null)
                  Text('First: ${fmtDay(r.first!.eventTime ?? r.first!.at)}',
                      style: numeric(size: 11.5, color: LookUpColors.grey)),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 12),
                const PosterFooter(),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
