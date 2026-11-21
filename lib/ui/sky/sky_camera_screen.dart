/// The whole sky over the camera: stars, constellation figures, planets, the
/// Moon, showpieces and any pass coming over, painted where they are even
/// when cloud, haze or a roof hides the real thing. Nothing points a
/// direction but Pip: it leaves the shutter and leads you to the best thing
/// up (or whatever you ask it to find), waits at the edge on the side to
/// turn, and lands on it once you've brought it to the middle; tap Pip to catch it. A catch is the only way into the Log: the picture
/// goes to your Photos and the sighting to the Log. The next sight counts
/// down in the top right.
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local_store.dart';
import '../../domain/finder/firefly.dart' show towardOnScreen;
import '../../domain/finder/guide_target.dart';
import '../../domain/finder/pointing.dart';
import '../../domain/models/sky_event.dart';
import '../../domain/plan/next_up.dart';
import '../../domain/sky/direction.dart';
import '../../domain/sky/wmm.dart';
import '../../services/orientation.dart';
import '../../services/photo_store.dart';
import '../../domain/plus/free_plan.dart';
import '../../state/providers.dart';
import '../../state/sky_state.dart';
import '../caught_it_screen.dart';
import '../finder_camera.dart';
import '../format.dart';
import '../kit/kit.dart';
import '../theme.dart';
import '../pip/pip_aim.dart';
import '../pro_camera_screen.dart';
import '../pip/pip_button.dart' show pipCameHome, pipHomeOffset;
import 'figure_spotlight.dart';
import 'sky_capture.dart';
import 'sky_thing.dart';
import 'sky_track.dart';

/// Opens with a fade, so Pip can be seen leaving its button beside the tabs
/// and, on Close, flying back down into it.
Future<void> openSkyCamera(
  BuildContext context, {
  required List<SkyThing> things,
  required List<SkyTrack> tracks,
  DateTime? time,
  double? lat,
  double? lon,
}) => Navigator.of(context).push(
  PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (_, _, _) => SkyCameraScreen(things: things, tracks: tracks, time: time, lat: lat, lon: lon),
    transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
  ),
);

/// The camera view of the sky as it is now, from outside Explore (Pip beside the
/// tab bar): the Moon, planets, showpieces and passes the live map shows.
Future<void> openLiveSkyCamera(BuildContext context, WidgetRef ref) async {
  final s = ref.read(settingsProvider).value;
  final lat = s?.latitude, lon = s?.longitude;
  final t = await ref.read(tonightSkyProvider.future);
  if (!context.mounted) return;
  if (t == null || lat == null || lon == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Set a location to see your sky.')));
    return;
  }
  final events = ref.read(homeProvider).value?.events ?? const <SkyEvent>[];
  return openSkyCamera(
    context,
    things: [
      SkyThing.moon(t.moon, lat, lon),
      for (final p in t.planets) SkyThing.planet(p, lat, lon),
      for (final x in t.showpieces) SkyThing.showpiece(x, lat, lon),
    ],
    tracks: [for (final e in upcomingPasses(events, DateTime.now().toUtc())) passTrack(e, lat, lon)],
    lat: lat,
    lon: lon,
  );
}

class SkyCameraScreen extends ConsumerStatefulWidget {
  const SkyCameraScreen({
    super.key,
    required this.things,
    required this.tracks,
    this.time,
    this.lat,
    this.lon,
    this.orientationStream,
    this.camera = true,
  });
  final List<SkyThing> things;
  final List<SkyTrack> tracks;

  /// Where the sky map is standing, when it isn't home (a famous night).
  final double? lat, lon;

  /// A moment the Sky map was moved to; null follows the clock.
  final DateTime? time;

  /// Injected in tests; defaults to the fused rotation sensor.
  final Stream<List<double>>? orientationStream;

  /// Start with the camera on (tests turn it off).
  final bool camera;

  @override
  ConsumerState<SkyCameraScreen> createState() => _SkyCameraState();
}

class _SkyCameraState extends ConsumerState<SkyCameraScreen> with SingleTickerProviderStateMixin, FigureSpotlight {
  StreamSubscription<List<double>>? _sub;
  List<double>? _r;
  String? _error;
  late bool _cameraOn = widget.camera;
  double? _previewHeight;
  double _declination = 0;

  /// The cloud and figure-8 hint, shown the first time only.
  late final bool _hint;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    final s = ref.read(settingsProvider).value;
    _hint = !(s?.skyCameraCoached ?? true);
    if (_hint) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(settingsProvider.notifier).edit((s) => s.copyWith(skyCameraCoached: true));
      });
    }
    _declination = declinationDeg(s?.latitude ?? 0, s?.longitude ?? 0, DateTime.now().toUtc());
    var stream = widget.orientationStream;
    try {
      stream ??= deviceRotation();
    } catch (e) {
      _error = '$e';
    }
    _sub = stream?.listen((r) => setState(() => _r = r), onError: (e) => setState(() => _error = '$e'));
    if (stream == null) _error ??= 'This device has no orientation sensor.';
  }

  @override
  void dispose() {
    _sub?.cancel();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  final _camera = GlobalKey<CameraBackdropState>();
  bool _catching = false;

  /// How close to the middle counts as "on it", for naming and for Pip.
  static const _lockDeg = 10.0;

  /// What you asked Pip to find ("Find something else"); null is Pip's pick.
  String? _guideId;

  /// Closing: Pip is flying back down to its button; then the screen goes.
  bool _leaving = false, _left = false;

  /// How long Pip takes to fly home before the camera fades away.
  static const _flyHome = Duration(milliseconds: 650);

  /// Close: Pip flies back to its button beside the tabs, then the camera
  /// fades out and the button's Pip lands. Straight away with Reduce Motion
  /// or when Pip isn't out.
  void _leave({required bool pipOut}) {
    if (_leaving) return;
    void go() {
      if (!mounted) return;
      setState(() => _left = true);
      pipCameHome.value++;
      // Once the rebuild lets this screen go.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }

    if (!pipOut || MediaQuery.disableAnimationsOf(context)) return go();
    setState(() => _leaving = true);
    Timer(_flyHome, go);
  }

  /// The overlay as it was last drawn, without its live hooks, for a catch.
  SkyOverlayPainter Function()? _still;

  /// Takes the picture and, with something in the middle, logs it: the
  /// picture to Photos (and LookUp's copy to the Log), then the celebration.
  Future<void> _catch(_Centred? c, {String? place}) async {
    void say(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    if (_catching) return;
    if (widget.time != null) return say('Back to now to catch something: this is the sky at another time.');
    if (!_cameraOn) {
      setState(() => _cameraOn = true);
      return say('Camera on. Point at it and tap Pip again.');
    }
    setState(() => _catching = true);
    try {
      HapticFeedback.mediumImpact();
      final shot = await _camera.currentState?.takePicture();
      final still = _still;
      if (!mounted) return;
      if (shot == null || still == null) return say('Couldn\'t take the picture.');
      final now = DateTime.now();
      final settings = ref.read(settingsProvider).value;
      final png = await composeSkyPicture(
        photo: shot,
        screen: MediaQuery.sizeOf(context),
        overlay: still(),
        title: c?.name ?? 'The night sky',
        line: '${fmtDay(now.toUtc())} · ${fmtTime(now.toUtc())}${place == null ? '' : ' · $place'}',
        // Always on free; LookUp+ can turn it off in Settings.
        caption: FreePlan.caption(isPlus: settings?.isPlus ?? false, wanted: settings?.photoCaption ?? true),
      );
      if (!mounted) return;
      if (png == null) return say('Couldn\'t take the picture.');
      final e = c?.event(now);
      final saved = await ref.read(photoLibraryProvider).save(png, name: 'LookUp-${now.millisecondsSinceEpoch}');
      if (!mounted) return;
      if (e == null) {
        return say(
          saved
              ? 'Saved to Photos. Bring something to the middle to catch it for your Log.'
              : 'Couldn\'t save to Photos. Allow LookUp to add photos in Settings.',
        );
      }
      final store = ref.read(storeProvider);
      final name = await const PhotoStore().saveBytes(e.id, png);
      await store.addFeedback(SeenFeedback.forEvent(e, seen: true, place: place));
      await store.setPhoto(e.id, name);
      ref.invalidate(skyLogProvider);
      if (!mounted) return;
      if (!saved) say('In your Log. Allow LookUp to add photos in Settings to keep a copy in Photos too.');
      await showCaughtIt(context, e);
    } finally {
      if (mounted) setState(() => _catching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider).value;
    figureFadeOn = !MediaQuery.disableAnimationsOf(context);
    // The sky drawn is the map's place; the compass is always where you are.
    final lat = widget.lat ?? s?.latitude, lon = widget.lon ?? s?.longitude;
    final now = widget.time ?? ref.watch(clockProvider).value ?? DateTime.now();
    final utc = now.toUtc();
    final r = _r;
    // Each mark with the thing it is, so a catch knows what it caught.
    final mapped = [
      for (final t in widget.things)
        if (t.position(utc) case final h when h.altitudeDeg > -1)
          (
            thing: t,
            mark: (
              label: t.id == 'moon' ? 'Moon' : t.name,
              d: SkyDir(h.azimuthDeg, h.altitudeDeg),
              bright: t.id == 'moon' || t.kind == 'Planet',
            ),
          ),
    ];
    final marks = <OverlayMark>[for (final m in mapped) m.mark];
    final tracks = <OverlayTrack>[
      for (final tr in widget.tracks)
        (
          label: eventTitle(tr.event),
          path: [for (final p in tr.points) (t: p.t, d: SkyDir(p.h.azimuthDeg, p.h.altitudeDeg))],
          now: switch (tr.at(utc)) {
            final h? => SkyDir(h.azimuthDeg, h.altitudeDeg),
            null => null,
          },
          color: tr.color,
        ),
    ];
    final camera = r == null ? null : cameraDirection(r, declinationDeg: _declination);
    // Whatever sits nearest the middle of the view, if anything's close: a
    // pass going over now first, then the Moon, planets and showpieces.
    _Centred? centred;
    if (camera != null) {
      // The same reach as Pip's lock below, so "That's Saturn" and Pip
      // landing on it happen together.
      double best = _lockDeg;
      for (final tr in widget.tracks) {
        if (tr.at(utc) case final h?) {
          final d = angularDistanceDeg(camera, SkyDir(h.azimuthDeg, h.altitudeDeg));
          if (d < best) (best, centred) = (d, _Centred(eventTitle(tr.event), (_) => tr.event));
        }
      }
      if (centred == null) {
        for (final m in mapped) {
          final d = angularDistanceDeg(camera, m.mark.d);
          if (d < best && lat != null && lon != null) {
            best = d;
            final t = m.thing;
            centred = _Centred(m.mark.label == 'Moon' ? 'the Moon' : m.mark.label, (now) => t.asEvent(now, lat, lon));
          }
        }
      }
    }
    // Pip's guide: the thing it leads you to (a pass going over now, else
    // the brightest planet, else the Moon...), where it is, and which way to
    // turn. Pip flies out to it; you bring it to the middle.
    final guides = <String, ({String name, SkyDir d})>{};
    final candidates = <GuideCandidate>[
      for (final tr in widget.tracks)
        if (tr.at(utc) case final h?)
          GuideCandidate(id: tr.event.id, kind: 'pass', mag: -3, altitudeDeg: h.altitudeDeg, live: true),
      for (final m in mapped)
        GuideCandidate(
          id: m.thing.id,
          kind: m.thing.id == 'moon' ? 'moon' : (m.thing.kind == 'Planet' ? 'planet' : 'other'),
          mag: m.thing.mag,
          altitudeDeg: m.mark.d.elevationDeg,
        ),
    ];
    for (final tr in widget.tracks) {
      if (tr.at(utc) case final h?) {
        guides[tr.event.id] = (name: eventTitle(tr.event), d: SkyDir(h.azimuthDeg, h.altitudeDeg));
      }
    }
    for (final m in mapped) {
      guides[m.thing.id] = (name: m.mark.label == 'Moon' ? 'the Moon' : m.mark.label, d: m.mark.d);
    }
    final aim = widget.time != null ? null : guideTarget(candidates, chosen: _guideId);
    final target = aim == null ? null : guides[aim.id];
    // The Pro camera (LookUp+) on whatever Pip is leading you to.
    ShotTarget? proTarget;
    if (aim != null && lat != null && lon != null) {
      final thing = mapped.where((m) => m.thing.id == aim.id).firstOrNull?.thing;
      final track = widget.tracks.where((tr) => tr.event.id == aim.id).firstOrNull;
      proTarget = thing != null ? ShotTarget.ofThing(thing) : (track == null ? null : ShotTarget.ofEvent(track.event, lat, lon));
    }
    final g = camera == null || target == null ? null : guide(camera, target.d, toleranceDeg: _lockDeg);
    final screen = MediaQuery.sizeOf(context);
    final onScreen = r == null || target == null
        ? null
        : projectToScreen(r, target.d, declinationDeg: _declination, previewHeightPx: _previewHeight ?? screen.height);
    final others = guideOrder(candidates).length > 1;
    // Pip's home: the button beside the tabs it came from.
    final home = pipHomeOffset(screen, MediaQuery.paddingOf(context));
    final passing = widget.tracks.where((tr) => tr.liveAt(utc)).map((tr) => eventTitle(tr.event)).toList();
    final status = widget.time != null
        ? 'The sky at ${fmtSkyMoment(utc, lon ?? 0)}'
        : passing.isNotEmpty
        ? '${passing.join(' and ')} going over now'
        : 'Live sky';
    // The next sight, counting down in the top right; not when looking at
    // another time.
    final next = widget.time != null ? null : nextUp(ref.watch(homeProvider).value?.events ?? const [], utc);
    final catalog = ref.watch(skyCatalogProvider).value;
    final art = (s?.skyFigures ?? true) ? figureArt : null;
    final place = s?.placeName;
    SkyOverlayPainter overlay({bool live = true, required double height, TextStyle labelStyle = const TextStyle()}) =>
        SkyOverlayPainter(
          r: r!,
          declinationDeg: _declination,
          now: utc,
          previewHeightPx: height,
          labelStyle: labelStyle,
          catalog: catalog,
          latDeg: lat!,
          lonDeg: lon!,
          tracks: tracks,
          marks: marks,
          art: art,
          glow: live ? figureGlow : null,
          onSpotlit: live ? onFigureSpotlit : null,
          twinkle: live && figureFadeOn ? figureTwinkle : null,
        );
    final pipOut = g != null && target != null;
    return PopScope(
      canPop: _left,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave(pipOut: pipOut);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (_cameraOn)
              Positioned.fill(
                child: CameraBackdrop(
                  key: _camera,
                  onHeight: (h) => _previewHeight = h,
                  onError: (msg) {
                    if (!mounted) return;
                    setState(() => _cameraOn = false);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                  },
                ),
              ),
            if (r != null && lat != null && lon != null)
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final labels = Theme.of(context).textTheme.labelSmall ?? const TextStyle();
                    final height = _previewHeight ?? c.maxHeight;
                    _still = () => overlay(live: false, height: height, labelStyle: labels);
                    return CustomPaint(
                      painter: overlay(height: height, labelStyle: labels),
                    );
                  },
                ),
              ),
            // Pip, out over the sky: it sets off from the shutter, flies to what
            // it's leading you to (or waits at the edge on the side to turn),
            // and lands on it, as the plain light, once it's in the middle.
            if (g != null && target != null)
              Positioned.fill(
                child: PipAim(
                  key: const Key('sky-pip'),
                  mode: PipMode.find,
                  // Leaving: Pip heads home, to its button beside the tabs.
                  target: _leaving ? home : onScreen,
                  toward: towardOnScreen(g),
                  distanceDeg: _leaving ? 40 : g.distanceDeg,
                  onTarget: !_leaving && g.onTarget,
                  canLock: !_leaving,
              homeward: _leaving,
                  words: _leaving ? 'Pip is heading home' : '${g.words} for ${target.name}',
                  // The sky already names it; and no ring: Pip is all there is.
                  ring: false,
                  // Sets off from its button beside the tabs.
                  launchFrom: home,
                ),
              ),
            // On it: tap Pip itself (where it sits, on the thing) to catch it.
            if (g != null && g.onTarget && !_leaving)
              Positioned(
                left: screen.width / 2 + (onScreen?.x ?? 0) - 70,
                top: screen.height / 2 + (onScreen?.y ?? 0) - 70,
                child: Semantics(
                  button: true,
                  label: 'Catch ${centred?.name ?? target!.name}',
                  excludeSemantics: true,
                  child: GestureDetector(
                    key: const Key('pip-on-target'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _catch(centred, place: place),
                    child: const SizedBox.square(dimension: 140),
                  ),
                ),
              ),
            // The controls fade as Pip flies home.
            AnimatedOpacity(
              opacity: _leaving ? 0 : 1,
              duration: const Duration(milliseconds: 220),
              child: IgnorePointer(
                ignoring: _leaving,
                child: SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: ScanTopBar(
                          onClose: () => _leave(pipOut: pipOut),
                          title: scanTitle(status),
                          // The next sight's countdown: easy to find, top right.
                          trailing: next == null ? const SizedBox(width: 44) : _Countdown(next, now: utc),
                        ),
                      ),
                      if (_hint)
                        const ScanHint(
                          'Cloud or a roof in the way? Everything is still drawn where it is. '
                          'Wave the phone in a figure-8 if it drifts.',
                        ),
                      const Spacer(),
                      if (others && camera != null && widget.time == null)
                        TextButton.icon(
                          key: const Key('find-something-else'),
                          onPressed: () => setState(() => _guideId = nextGuideTarget(candidates, aim?.id)?.id),
                          icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                          label: const Text('Pip, find something else'),
                          style: TextButton.styleFrom(
                            foregroundColor: LookUpColors.white,
                            backgroundColor: Colors.black.withValues(alpha: 0.45),
                          ),
                        ),
                      // Nerd mode: exactly where the phone points.
                      if ((s?.nerdMode ?? false) && camera != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            nerdPosition(camera.azimuthDeg, camera.elevationDeg),
                            key: const Key('nerd-numbers'),
                            style: numeric(
                              size: 13,
                              color: LookUpColors.grey,
                            ).copyWith(shadows: const [Shadow(blurRadius: 6)]),
                          ),
                        ),
                      ScanLine(
                        camera == null
                            ? (_error != null
                                  ? 'No motion sensor here, so this view can\'t follow the phone.'
                                  : 'Hold your phone up to the sky')
                            : centred != null
                            ? 'That\'s ${centred.name}. Tap Pip to catch it!'
                            : g != null
                            ? '${g.words} for ${target!.name}'
                            : 'Looking ${compassWord(camera.azimuthDeg)}, ${elevationWord(camera.elevationDeg)}',
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                        child: Row(
                          children: [
                            CircleButton(
                              tooltip: _cameraOn ? 'Hide camera' : 'Show camera',
                              icon: _cameraOn ? Icons.videocam_off_rounded : Icons.videocam_rounded,
                              onPressed: () => setState(() => _cameraOn = !_cameraOn),
                            ),
                            Expanded(
                              child: Center(
                                // The shutter: Pip's home, which it leaves to guide you.
                                // Green once something is in the middle; a tap here or
                                // on Pip catches it.
                                child: Semantics(
                                  button: true,
                                  label: centred != null ? 'Catch ${centred.name}' : 'Take a picture of the sky',
                                  excludeSemantics: true,
                                  child: GestureDetector(
                                    key: const Key('shutter'),
                                    onTap: () => _catch(centred, place: place),
                                    child: Container(
                                      width: 80,
                                      height: 80,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.black.withValues(alpha: 0.35),
                                        border: Border.all(
                                          color: centred != null
                                              ? fireflyGlow.withValues(alpha: 0.9)
                                              : Colors.white.withValues(alpha: 0.35),
                                          width: 3,
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      child: Icon(
                                        Icons.camera_rounded,
                                        size: 34,
                                        color: _catching
                                            ? LookUpColors.greyDim
                                            : centred != null
                                            ? fireflyGlow
                                            : LookUpColors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            CircleButton(
                              key: const Key('pro-camera'),
                              tooltip: 'Pro camera',
                              icon: Icons.tune_rounded,
                              onPressed: proTarget == null ? null : () => openProCamera(context, ref, proTarget!),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What's in the middle of the view: its name in words, and the sighting it
/// would be once caught.
class _Centred {
  const _Centred(this.name, this.event);
  final String name;
  final SkyEvent Function(DateTime now) event;
}

/// "ISS · 12m 04s" in the top right, "ISS · now" while it's over.
class _Countdown extends StatelessWidget {
  const _Countdown(this.e, {required this.now});
  final SkyEvent e;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final live = !now.isBefore(e.start);
    final words = live ? 'now' : fmtCountdown(e.start.difference(now));
    return Semantics(
      label: live ? '${eventTitle(e)}, going over now' : '${eventTitle(e)} in $words',
      excludeSemantics: true,
      child: Container(
        key: const Key('camera-countdown'),
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: live ? LookUpColors.good : LookUpColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              eventStyle(e.type, details: e.details).icon ?? Icons.circle,
              size: 16,
              color: eventStyle(e.type, details: e.details).color,
            ),
            const SizedBox(width: 6),
            Text(
              '${eventShortName(e)} ',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: LookUpColors.grey),
            ),
            Text(
              words,
              style: numeric(size: 15, weight: FontWeight.w700, color: live ? LookUpColors.good : LookUpColors.white),
            ),
          ],
        ),
      ),
    );
  }
}
