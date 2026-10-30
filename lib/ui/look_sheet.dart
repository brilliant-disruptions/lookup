import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/local_store.dart';
import '../domain/models/sky_event.dart';
import '../domain/sky/direction.dart';
import '../domain/sky/landmarks.dart';
import '../services/photo_store.dart';
import '../state/providers.dart';
import '../state/sky_state.dart';
import 'calendar.dart';
import 'finder_screen.dart';
import 'photo_tips.dart';
import 'share_card.dart';
import 'sky/sky_track.dart';
import 'sky_snapshot.dart';
import 'format.dart';
import 'kit/kit.dart';
import 'theme.dart';
import 'widgets/compass_arrow.dart';
import 'widgets/countdown_ring.dart';
import 'widgets/station_facts.dart';
import 'widgets/pass_timeline.dart';

Future<void> showLookSheet(BuildContext context, SkyEvent event) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => LookSheet(event: event),
    );

/// What the notification opens: countdown, where to look, timeline, share.
/// After the event: "Did you see it?" (spec §3.3), stored on-device.
class LookSheet extends ConsumerStatefulWidget {
  const LookSheet({super.key, required this.event, this.demo = false});
  final SkyEvent event;

  /// Preview mode: labelled, nothing stored, no share.
  final bool demo;
  @override
  ConsumerState<LookSheet> createState() => _LookSheetState();
}

class _LookSheetState extends ConsumerState<LookSheet> {
  bool? _seen;
  bool _askingWhy = false;
  bool _photoAdded = false;

  Future<void> _addPhoto() async {
    try {
      final name = await const PhotoStore().pickFor(event.id);
      if (name == null) return;
      await ref.read(storeProvider).setPhoto(event.id, name);
      ref.invalidate(skyLogProvider);
      if (mounted) setState(() => _photoAdded = true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Couldn\'t open your photos. Check Photos access in Settings.')));
    }
  }

  SkyEvent get event => widget.event;

  @override
  void initState() {
    super.initState();
    // Opening an event that's about to start: put the countdown on the Lock
    // Screen / Dynamic Island (iOS 16.2+, once the widget extension exists).
    if (!widget.demo && event.details['past'] != true) {
      unawaited(ref.read(liveActivityProvider).startIfSoon(event));
    }
  }

  Future<void> _answer(bool seen, {String? reason}) async {
    if (widget.demo) {
      setState(() {
        _seen = seen;
        _askingWhy = !seen && reason == null;
      });
      return;
    }
    await ref.read(storeProvider).addFeedback(SeenFeedback.forEvent(event,
        seen: seen, reason: reason, place: ref.read(settingsProvider).value?.placeName));
    ref.invalidate(skyLogProvider);
    if (!mounted) return;
    setState(() {
      _seen = seen;
      _askingWhy = !seen && reason == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final t = Theme.of(context).textTheme;
    final nowUtc = now.toUtc();
    final live = !nowUtc.isBefore(event.start) && nowUtc.isBefore(event.end);
    final over = !nowUtc.isBefore(event.end);
    final isAurora = event.type == SkyEventType.auroraNow || event.type == SkyEventType.auroraOutlook;
    final isPass = event.type == SkyEventType.iss || event.type == SkyEventType.tiangong ||
        event.type == SkyEventType.starlinkTrain || event.type == SkyEventType.satellitePass;
    final isTransit = event.type == SkyEventType.issTransit;
    final place = ref.watch(settingsProvider).value?.placeName;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.demo)
              const Padding(
                padding: EdgeInsets.only(bottom: 14),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Pill('Preview · a pass in fast-forward', icon: Icons.fast_forward_rounded, color: LookUpColors.blue),
                ),
              ),
            Row(children: [
              EventGlyph.of(event, size: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(event.details['past'] == true ? pastTitle(event) : eventTitle(event),
                      style: display(24, weight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    event.details['past'] == true
                        ? '${fmtDay(event.start)} · ${pastVerdict(event)}'
                        : '${fmtDay(event.start)} · ${fmtTime(event.start)}',
                    style: numeric(size: 14, color: LookUpColors.grey),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 20),
            Semantics(
              liveRegion: true,
              child: over
                  ? Text('That one\'s over', style: display(30, weight: FontWeight.w700, color: LookUpColors.grey))
                  : live
                      ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Kicker('Happening now', color: eventStyle(event.type).color, live: true),
                          const SizedBox(height: 6),
                          CountdownText('${fmtCountdown(event.end.difference(nowUtc))} left', size: 52),
                        ])
                      : CountdownText('in ${fmtCountdown(event.start.difference(nowUtc))}', size: 52),
            ),
            const SizedBox(height: 22),
            Center(
              child: Semantics(
                label: 'Compass arrow pointing ${compassWord(isAurora ? 0 : (isPass ? event.riseAzimuthDeg : event.peakAzimuthDeg))}',
                child: CountdownRing(
                  progress: event.details['past'] == true ? null : ringProgress(event, now),
                  live: live,
                  child: CompassArrow(azimuthDeg: isAurora ? 0 : (isPass ? event.riseAzimuthDeg : event.peakAzimuthDeg)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              lookLine(event),
              textAlign: TextAlign.center,
              style: t.bodyLarge,
            ),
            if (isPass) _Landmarks(event: event),
            if (isTransit && ((event.details['travelKm'] as num?) ?? 0) >= 0.5 && !over)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: OutlinedButton.icon(
                  onPressed: () => openDirections(
                      (event.details['siteLat'] as num).toDouble(), (event.details['siteLon'] as num).toDouble()),
                  icon: const Icon(Icons.directions_car_outlined),
                  label: const Text('Directions to the spot'),
                ),
              ),
            // While it's happening (and in the preview) the arc is the point.
            if (isPass && (live || widget.demo)) ...[
              const SizedBox(height: 18),
              PassTimeline(event: event, now: now),
            ],
            const SizedBox(height: 22),
            if (!over && event.details['past'] != true)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FilledButton.icon(
                  onPressed: () => openFinder(context, event),
                  icon: const Icon(Icons.explore_rounded),
                  label: const Text('Find it in the sky'),
                ),
              ),
            if (widget.demo && over)
              _demoDone(context)
            else if (over || live)
              _feedbackRow(context, place)
            else
              _plainRow(context, place),
            if (!widget.demo) _details(context, now, isPass: isPass, showArc: !live, isTransit: isTransit),
          ],
        ),
      ),
    );
  }

  Widget _demoDone(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('That\'s a LookUp night.', textAlign: TextAlign.center, style: display(22, weight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text('The real one taps you 10 minutes before, then again at one minute. Afterwards it asks if you saw it.',
            textAlign: TextAlign.center, style: TextStyle(color: LookUpColors.grey, height: 1.4)),
        const SizedBox(height: 14),
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Got it')),
      ]);

  /// Before the event: quiet secondary actions (the demo just needs a way out).
  Widget _plainRow(BuildContext context, String? place) {
    if (widget.demo) {
      return FilledButton.icon(
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.check_rounded),
        label: const Text('Got it'),
      );
    }
    return Row(children: [
      Expanded(
        child: OutlinedButton.icon(
          onPressed: () => addToCalendar(event, place: place),
          icon: const Icon(Icons.event_rounded, size: 18),
          label: const Text('Calendar'),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: OutlinedButton.icon(
          onPressed: () => showShareCard(context, event, mode: ShareMode.invite),
          icon: const Icon(Icons.person_add_alt_rounded, size: 18),
          label: const Text('Invite'),
        ),
      ),
    ]);
  }

  /// Everything that isn't "where and when", folded away: the arc or the
  /// numbers, brightness and cloud, who's aboard, photo tips.
  Widget _details(BuildContext context, DateTime now,
      {required bool isPass, required bool showArc, required bool isTransit}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 4),
          title: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('Details', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: LookUpColors.grey)),
            SizedBox(width: 2),
            Icon(Icons.expand_more_rounded, size: 20, color: LookUpColors.grey),
          ]),
          showTrailingIcon: false,
          children: [
            const Divider(),
            const SizedBox(height: 18),
            if (isPass && showArc)
              Semantics(
                label: 'Rises ${compassWord(event.riseAzimuthDeg)} at ${fmtTime(event.start)}, '
                    'peaks ${event.peakElevationDeg.round()} degrees at ${fmtTime(event.peak)}, '
                    'sets ${compassWord(event.setAzimuthDeg)} at ${fmtTime(event.end)}',
                child: PassTimeline(event: event, now: now),
              )
            else if (!isPass)
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                for (final (k, v) in statsFor(event)) StatTile(k: k, v: v, align: CrossAxisAlignment.center),
              ]),
            const SizedBox(height: 18),
            Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
              if (event.details['brightness'] is String)
                Pill(_capitalised('${event.details['brightness']}'), icon: Icons.light_mode_rounded, color: LookUpColors.gold),
              CloudPill(event.cloudCoverPercent),
              if (event.isEstimate) const Pill('Estimate: orbit data is a few days old', color: LookUpColors.warn),
            ]),
            if (event.type == SkyEventType.iss || event.type == SkyEventType.tiangong) StationFacts(event: event),
            if (isTransit)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Path is ~${((event.details['halfWidthKm'] as num?) ?? 0) * 2 ~/ 1} km wide. Orbits shift a little day to day, so check again the evening before.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: LookUpColors.greyDim, fontSize: 12, height: 1.35),
                ),
              ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => showPhotoTips(context, event.type),
              icon: const Icon(Icons.photo_camera_rounded, size: 18),
              label: const Text('Photo tips'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _feedbackRow(BuildContext context, String? place) {
    final t = Theme.of(context).textTheme;
    if (_seen == true) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Glad you caught it.', textAlign: TextAlign.center, style: display(22, weight: FontWeight.w700)),
        const SizedBox(height: 12),
        Row(children: [
          if (!widget.demo) ...[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _addPhoto,
                icon: Icon(_photoAdded ? Icons.check_rounded : Icons.add_a_photo_rounded),
                label: Text(_photoAdded ? 'Photo added' : 'Add your photo'),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: FilledButton.icon(
              onPressed: () => showShareCard(context, event),
              icon: const Icon(Icons.ios_share_rounded),
              label: const Text('Share it'),
            ),
          ),
        ]),
      ]);
    }
    if (_askingWhy) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('What got in the way?', textAlign: TextAlign.center, style: t.titleMedium),
        const SizedBox(height: 10),
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          for (final (label, key) in const [('Clouds', 'clouds'), ('Too low', 'too-low'), ('Missed it', 'missed')])
            OutlinedButton(onPressed: () => _answer(false, reason: key), child: Text(label)),
        ]),
      ]);
    }
    if (_seen == false) {
      return const Text('Thanks. We\'ll be pickier next time.', textAlign: TextAlign.center, style: TextStyle(color: LookUpColors.grey));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Did you see it?', textAlign: TextAlign.center, style: display(22, weight: FontWeight.w700)),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: () => _answer(false), child: const Text('No'))),
        const SizedBox(width: 12),
        Expanded(child: FilledButton(onPressed: () => _answer(true), child: const Text('Yes!'))),
      ]),
    ]);
  }
}

String _capitalised(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// One plain sentence: where to look and what you'll see.
String lookLine(SkyEvent e) => switch (e.type) {
      SkyEventType.auroraNow || SkyEventType.auroraOutlook =>
        'Face north. Get away from streetlights and give your eyes five minutes.',
      SkyEventType.meteorShower =>
        'Lie back and look up, anywhere. Meteors seem to come from the ${compassWord(e.peakAzimuthDeg)}, but they streak across the whole sky. Give your eyes 20 minutes in the dark.',
      SkyEventType.lunarEclipse =>
        'Look ${compassWord(e.peakAzimuthDeg)} at the Moon, ${elevationWord(e.peakElevationDeg)}. It darkens and turns copper-red at its deepest.',
      SkyEventType.planetPairing =>
        '${e.details['label']}: two bright points ${e.details['separation']}° apart, ${elevationWord(e.peakElevationDeg)} in the ${compassWord(e.peakAzimuthDeg)}. Hold your thumb out at arm\'s length: they fit behind it.',
      SkyEventType.rocketLaunch =>
        'Look ${compassWord(e.peakAzimuthDeg)}, low on the horizon. A bright point climbs and arcs away; at twilight the plume glows like a jellyfish.',
      SkyEventType.planetHighlight || SkyEventType.skyObject =>
        'Look ${compassWord(e.peakAzimuthDeg)}, ${elevationWord(e.peakElevationDeg)}. ${e.details['look'] ?? 'Planets shine with a steady light; stars twinkle.'}',
      SkyEventType.issTransit => e.details['body'] == 'Moon'
          ? 'The station\'s silhouette crosses the Moon, ${elevationWord(e.peakElevationDeg)} in the ${compassWord(e.peakAzimuthDeg)}. It\'s over in ${fmtSeconds(transitCrossing(e))}: aim binoculars or a camera at the Moon and start shooting a few seconds early.'
          : 'Cameras only: never look at the Sun without a certified solar filter. The station\'s silhouette crosses the Sun in ${fmtSeconds(transitCrossing(e))}. Burst-shoot through a solar filter from a few seconds before.',
      _ =>
        'Face ${compassWord(e.riseAzimuthDeg)}. It appears there and climbs ${elevationWord(e.peakElevationDeg)} before fading out toward the ${compassWord(e.setAzimuthDeg)}.',
    };

/// Three stat tiles for non-pass events.
List<(String, String)> statsFor(SkyEvent e) => switch (e.type) {
      SkyEventType.meteorShower => [
          ('Best', fmtTime(e.peak)),
          ('Per hour', '~${e.details['perHour']}'),
          ('Moon', '${(((e.details['moonIllumination'] as num?) ?? 0) * 100).round()}%'),
        ],
      SkyEventType.lunarEclipse => [
          ('Starts', fmtTime(e.start)),
          ('Deepest', fmtTime(e.peak)),
          ('Ends', fmtTime(e.end)),
        ],
      SkyEventType.planetPairing => [
          ('Apart', '${e.details['separation']}°'),
          ('Look', compassAbbrev(e.peakAzimuthDeg)),
          ('Height', '${e.peakElevationDeg.round()}°'),
        ],
      SkyEventType.rocketLaunch => [
          ('Liftoff', fmtTime(e.start)),
          ('Away', '${e.details['distanceKm']} km'),
          ('Look', compassAbbrev(e.peakAzimuthDeg)),
        ],
      SkyEventType.planetHighlight || SkyEventType.skyObject => [
          ('Look', compassAbbrev(e.peakAzimuthDeg)),
          ('Height', '${e.peakElevationDeg.round()}°'),
          ('Mag', (e.details['magnitude'] as num?)?.toStringAsFixed(1) ?? '–'),
        ],
      SkyEventType.issTransit => [
          ('At', fmtTimeSeconds(e.peak)),
          ('Lasts', fmtSeconds(transitCrossing(e))),
          ('Go', ((e.details['travelKm'] as num?) ?? 0) < 0.5
              ? 'Here'
              : '${(e.details['travelKm'] as num).round()} km ${compassAbbrev(((e.details['travelBearingDeg'] as num?) ?? 0).toDouble())}'),
        ],
      _ => [
          ('From', fmtTime(e.start)),
          ('Until', fmtTime(e.end)),
          ('Kp', (e.details['kp'] as num?)?.toStringAsFixed(1) ?? '–'),
        ],
    };

/// Turn-by-turn to a transit's centre line in the platform's maps app.
Future<void> openDirections(double lat, double lon) async {
  final url = defaultTargetPlatform == TargetPlatform.iOS
      ? Uri.parse('https://maps.apple.com/?daddr=$lat,$lon')
      : Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lon');
  try {
    await launchUrl(url, mode: LaunchMode.externalApplication);
  } catch (_) {}
}

/// Find it by what's there: the bright stars, planets and Moon the pass
/// really goes near, in words and drawn on the real sky.
class _Landmarks extends ConsumerStatefulWidget {
  const _Landmarks({required this.event});
  final SkyEvent event;
  @override
  ConsumerState<_Landmarks> createState() => _LandmarksState();
}

class _LandmarksState extends ConsumerState<_Landmarks> {
  // The sheet rebuilds every second for its countdown; the sky doesn't need to.
  Object? _key;
  Widget _built = const SizedBox.shrink();

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider).value;
    final catalog = ref.watch(skyCatalogProvider).value;
    final lat = s?.latitude, lon = s?.longitude;
    final key = (widget.event.id, lat, lon, catalog);
    if (key == _key) return _built;
    _key = key;
    if (lat == null || lon == null || catalog == null || catalog.stars.isEmpty) {
      return _built = const SizedBox.shrink();
    }
    final e = widget.event;
    final track = passTrack(e, lat, lon);
    final marks = landmarksAlong(
      track: [for (final p in track.points) (t: p.t, h: p.h)],
      catalog: catalog,
      lat: lat,
      lon: lon,
    );
    final words = landmarkWords(marks);
    if (words == null) return _built = const SizedBox.shrink();
    return _built = Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          'Look for it $words.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: LookUpColors.blue, height: 1.35),
        ),
        const SizedBox(height: 12),
        AspectRatio(
          aspectRatio: 16 / 10,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.md),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [LookUpColors.black, LookUpColors.night],
                ),
              ),
              child: SkySnapshot(
                catalog: catalog,
                utc: e.peak.toUtc(),
                lat: lat,
                lon: lon,
                centerAz: e.peakAzimuthDeg,
                centerAlt: (e.peakElevationDeg * 0.55).clamp(12.0, 50.0),
                track: [for (final p in track.points) p.h],
                tint: track.color,
                labels: [for (final m in marks) (m.name == 'the Moon' ? 'Moon' : m.name, m.position)],
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
