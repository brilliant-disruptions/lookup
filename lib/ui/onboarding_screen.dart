import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/finder/pointing.dart' show SkyDir;
import '../domain/models/settings.dart';
import '../domain/models/sky_event.dart';
import '../domain/onboarding/first_look.dart';
import '../domain/plus/plus_preview.dart';
import '../state/providers.dart';
import '../state/sky_state.dart';
import 'format.dart';
import 'kit/kit.dart';
import 'onboarding/first_look_sky.dart';
import 'onboarding/globe.dart';
import 'onboarding/twilight_slider.dart';
import 'paywall_sheet.dart';
import 'places_screen.dart';
import 'sky/sky_thing.dart';
import 'sky/sky_track.dart';
import 'theme.dart';

/// Follow Pip: onboarding teaches the app by doing it, on their own sky.
///
/// Tap the light and Pip wakes. Pip asks roughly where they are (or a town),
/// a globe turns to find it, and their real sky appears (right now if it's
/// dark, else tonight): they drag it to follow Pip, which lands on the
/// brightest thing up, and tap Pip to catch it. Then tonight's space station
/// pass in fast-forward (or a practice one), the day slider that shows why
/// passes come at dusk and dawn, what Pip should tell them about, the alert
/// ask with their first real sight, and once, the LookUp+ offer.
///
/// Every catch here is practice: nothing reaches the Log.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingState();
}

/// The wall clock for onboarding's sped-up pass (tests move it).
@visibleForTesting
DateTime Function() onboardingClock = DateTime.now;

enum _Step { wake, hello, noLocation, looking, sky, station, why, pick, ask, offer }

class _OnboardingState extends ConsumerState<OnboardingScreen> {
  _Step _step = _Step.wake;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // The satellites and launches don't depend on where the user is: fetch
    // them while Pip says hello, so the sky only waits for the location.
    unawaited(ref.read(refreshServiceProvider).prefetch().catchError((_) {}));
  }

  void _go(_Step s) => setState(() => _step = s);

  Future<void> _showMe() async {
    setState(() => _busy = true);
    final ok = await ref.read(locationServiceProvider).requestPermission();
    if (!mounted) return;
    setState(() => _busy = false);
    ok ? await _look() : _go(_Step.noLocation);
  }

  Future<void> _pickTown() async {
    await openPlaces(context);
    if (!mounted) return;
    final s = await ref.read(settingsProvider.future);
    if (s.hasLocation) await _look();
  }

  /// The first refresh, while the globe turns, so the sky and the pass that
  /// follow are theirs. Quick first (location and the ISS only); clouds,
  /// aurora and Starlink follow in the background.
  Future<void> _look() async {
    _go(_Step.looking);
    final shown = Future<void>.delayed(const Duration(milliseconds: 1900));
    try {
      // Let the stored (empty) data finish loading first, or it can land
      // after the refresh and hide what it found.
      await ref.read(homeProvider.future);
      await ref.read(homeProvider.notifier).refresh(quick: true);
    } catch (_) {
      // Offline: the pages after this say so, and the shell retries.
    }
    unawaited(ref.read(homeProvider.notifier).refresh().catchError((_) {}));
    await shown; // let the globe finish turning
    if (!mounted || _step != _Step.looking) return;
    // Allowed, but no fix came (indoors, airplane mode): a town instead of a wait.
    final s = await ref.read(settingsProvider.future);
    if (!mounted) return;
    _go(s.hasLocation ? _Step.sky : _Step.noLocation);
  }

  Future<void> _finish({required bool alerts}) async {
    setState(() => _busy = true);
    if (alerts) {
      final granted = await ref.read(notificationServiceProvider).requestPermission();
      // Alerts were planned before permission; plan them again now they can land.
      // A refresh still running (onboarding's Starlink one) plans at its end,
      // so waiting for it here would only bring the download's wait back.
      if (granted) {
        final home = ref.read(homeProvider.notifier);
        if (!home.refreshing) {
          try {
            await home.refresh();
          } catch (_) {}
        }
      }
    }
    if (!mounted) return;
    // Once, and never to someone who already has LookUp+: what LookUp+ would
    // tap them for. Most trials start on day one; this is that moment.
    final s = await ref.read(settingsProvider.future);
    if (!s.isPlus && !s.trialOfferShown) {
      if (mounted) {
        setState(() {
          _busy = false;
          _step = _Step.offer;
        });
      }
      return;
    }
    await _done();
  }

  Future<void> _done() => ref
      .read(settingsProvider.notifier)
      .edit((s) => s.copyWith(onboarded: true, onboardedAt: DateTime.now().toUtc(), trialOfferShown: true));

  /// The offer's two ways out: a trial (through the paywall), or "Not now",
  /// which counts as a decline for the soft asks (domain/plus/nudges.dart).
  Future<void> _offer({required bool tryIt}) async {
    if (tryIt) {
      await showPaywall(context, headline: 'Every tap, for everything up there. Free for 7 days.');
      if (!mounted) return;
    }
    if (!(ref.read(settingsProvider).value?.isPlus ?? false)) {
      await ref.read(settingsProvider.notifier).edit((s) => s.copyWith(plusDeclines: s.plusDeclines + 1));
    }
    await _done();
  }

  @override
  Widget build(BuildContext context) => switch (_step) {
        _Step.wake => _WakePage(onWake: () => _go(_Step.hello)),
        _Step.hello || _Step.noLocation => _HelloPage(
            busy: _busy,
            denied: _step == _Step.noLocation,
            onShowMe: _showMe,
            onTown: _pickTown,
          ),
        _Step.looking => const _LookingPage(),
        _Step.sky => _SkyPage(onNext: () => _go(_Step.station)),
        _Step.station => _StationPage(onNext: () => _go(_Step.why)),
        _Step.why => _WhyPage(onNext: () => _go(_Step.pick)),
        _Step.pick => _PickPage(onNext: () => _go(_Step.ask)),
        _Step.ask => _AskPage(busy: _busy, onFinish: _finish),
        _Step.offer => _OfferPage(onTry: () => _offer(tryIt: true), onNotNow: () => _offer(tryIt: false)),
      };
}

/// The words over a sky page: big and plain, shadowed so they read on stars.
class _SkyWords extends StatelessWidget {
  const _SkyWords(this.title, {this.sub, super.key});
  final String title;
  final String? sub;
  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.25, shadows: [Shadow(blurRadius: 12), Shadow(blurRadius: 3)])),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(sub!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13.5, color: LookUpColors.grey, shadows: [Shadow(blurRadius: 8)])),
          ],
        ]),
      );
}

/// A practice catch: the flash, then what it was and one line about it.
class _CaughtCard extends StatelessWidget {
  const _CaughtCard({required this.kicker, required this.title, required this.fact, required this.onNext, this.color = LookUpColors.blue});
  final String kicker, title, fact;
  final Color color;
  final VoidCallback onNext;
  @override
  Widget build(BuildContext context) => Rise(
        index: 0,
        child: GlassCard(
          key: const Key('first-look-caught'),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Kicker(kicker, color: color),
            const SizedBox(height: 4),
            Text(title, style: display(22, weight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(fact, style: const TextStyle(color: LookUpColors.grey, height: 1.4)),
            const SizedBox(height: 14),
            FilledButton(onPressed: onNext, child: const Text('Next')),
          ]),
        ),
      );
}

/// A white flash, as a camera would, when something's caught.
class _Flash extends StatelessWidget {
  const _Flash({required this.on});
  final bool on;
  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: TweenAnimationBuilder<double>(
          key: ValueKey(on),
          tween: Tween(begin: on ? 0.85 : 0, end: 0),
          duration: const Duration(milliseconds: 450),
          builder: (_, v, _) => ColoredBox(color: Colors.white.withValues(alpha: v)),
        ),
      );
}

/// Moment 1: a faint light in the dark. Tap it, and it's Pip.
class _WakePage extends StatelessWidget {
  const _WakePage({required this.onWake});
  final VoidCallback onWake;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SkyBackdrop(
          child: GestureDetector(
            key: const Key('onboarding-wake'),
            behavior: HitTestBehavior.opaque,
            onTap: onWake,
            child: SafeArea(
              child: SizedBox.expand(
                child: Column(children: [
                const Spacer(flex: 3),
                Semantics(
                  button: true,
                  label: 'A faint light. Tap it to wake Pip.',
                  child: const PipMark(key: Key('onboarding-pip'), size: 90, asDot: true, blinking: true),
                ),
                const Spacer(flex: 2),
                const _SkyWords('Tap the light', sub: 'Someone\'s waiting for you'),
                const SizedBox(height: 48),
              ]),
              ),
            ),
          ),
        ),
      );
}

/// Moment 2: Pip, awake, asks where they are, and why. A "no" offers a town.
class _HelloPage extends StatelessWidget {
  const _HelloPage({required this.busy, required this.denied, required this.onShowMe, required this.onTown});
  final bool busy, denied;
  final VoidCallback onShowMe, onTown;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SkyBackdrop(
          child: SafeArea(
            child: _FillOrScroll(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Spacer(),
                const Center(child: PipMark(key: Key('onboarding-pip'), size: 150, state: PipState.greet)),
                const Spacer(),
                const Rise(index: 0, child: Kicker('Pip', color: LookUpColors.good)),
                const SizedBox(height: 8),
                Rise(index: 1, child: Text('Hi. I find things in the sky for you.', style: display(30, weight: FontWeight.w700, height: 1.12))),
                const SizedBox(height: 10),
                Rise(
                  index: 2,
                  child: Text(
                    denied
                        ? 'No problem. Tell me your town instead: a rough place is all I need.'
                        : 'Let\'s look at yours. Tell me roughly where you are, and I\'ll show you what\'s up there.',
                    style: const TextStyle(color: LookUpColors.grey, fontSize: 16, height: 1.4),
                  ),
                ),
                const SizedBox(height: 22),
                if (denied) ...[
                  FilledButton.icon(onPressed: onTown, icon: const Icon(Icons.search_rounded), label: const Text('Choose your town')),
                  TextButton(onPressed: busy ? null : onShowMe, child: const Text('Try location again')),
                ] else ...[
                  FilledButton(onPressed: busy ? null : onShowMe, child: Text(busy ? 'One moment…' : 'Show me my sky')),
                  TextButton(onPressed: busy ? null : onTown, child: const Text('Choose a town instead')),
                ],
                const SizedBox(height: 6),
                const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.lock_rounded, size: 14, color: LookUpColors.greyDim),
                  SizedBox(width: 6),
                  Flexible(child: Text('A rough location only, and it never leaves your phone.', style: TextStyle(fontSize: 12.5, color: LookUpColors.greyDim))),
                ]),
              ]),
            ),
          ),
        ),
      );
}

/// Moment 3: the globe turns to their place while LookUp works out its sky.
class _LookingPage extends ConsumerWidget {
  const _LookingPage();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider).value;
    return Scaffold(
      body: SkyBackdrop(
        child: SafeArea(
          child: Column(children: [
            const SizedBox(height: 40),
            const _SkyWords('Finding your sky…'),
            Expanded(
              child: s?.latitude == null
                  ? const Center(child: PipMark(size: 60, state: PipState.searching))
                  : FindingGlobe(key: const Key('onboarding-globe'), lat: s!.latitude!, lon: s.longitude!, place: s.placeName),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Moment 4: their real sky. Drag to follow Pip; tap Pip when it lands.
class _SkyPage extends ConsumerStatefulWidget {
  const _SkyPage({required this.onNext});
  final VoidCallback onNext;
  @override
  ConsumerState<_SkyPage> createState() => _SkyPageState();
}

class _SkyPageState extends ConsumerState<_SkyPage> {
  String? _name, _caughtId, _caughtName;
  bool _on = false;
  late final DateTime _opened = onboardingClock();

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider).value;
    final look = ref.watch(firstLookProvider);
    final catalog = ref.watch(skyCatalogProvider).value;
    final lat = s?.latitude, lon = s?.longitude;
    if (lat == null || lon == null || look.isLoading) {
      return const Scaffold(body: SkyBackdrop(child: Center(child: PipMark(size: 60, state: PipState.searching))));
    }
    final things = look.value?.things ?? const <SkyThing>[];
    final when = firstLookTime(_opened, look.value?.window);
    final visible = things.where((t) => t.position(when.at).altitudeDeg > 5).toList();
    if (visible.isEmpty) {
      // Nothing bright up tonight (or the sky couldn't be worked out): on to the station.
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onNext());
      return const Scaffold(body: SkyBackdrop(child: SizedBox.expand()));
    }
    final place = (s?.placeName?.isNotEmpty ?? false) ? s!.placeName! : 'you';
    final whenWords = when.isNow ? 'Over $place, right now' : 'Over $place tonight at ${fmtTime(when.at)}';
    final caught = _caughtId != null;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Positioned.fill(
          child: FirstLookSky(
            key: const Key('first-look'),
            things: visible,
            lat: lat,
            lon: lon,
            catalog: catalog,
            clock: () => when.at,
            enabled: !caught,
            onStatus: (name, on) => setState(() {
              _name = name;
              _on = on;
            }),
            onCatch: (id, name) => setState(() {
              _caughtId = id;
              _caughtName = name;
            }),
          ),
        ),
        Positioned.fill(child: _Flash(on: caught)),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _SkyWords(
                caught
                    ? 'Got it!'
                    : _on
                        ? 'That\'s ${_name ?? 'it'}. Tap Pip to catch it!'
                        : 'Drag the sky. Follow Pip.',
                sub: whenWords,
                key: const Key('first-look-words'),
              ),
              const Spacer(),
              if (caught)
                _CaughtCard(
                  kicker: 'Practice catch · $whenWords',
                  title: 'You found ${_caughtName!}',
                  fact: firstLookFact(_caughtId!, _caughtName!),
                  color: LookUpColors.good,
                  onNext: widget.onNext,
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Moment 5: tonight's space station pass in fast-forward (a practice pass
/// when none is coming soon). Pip rides it; tap Pip to catch the preview.
class _StationPage extends ConsumerStatefulWidget {
  const _StationPage({required this.onNext});
  final VoidCallback onNext;
  @override
  ConsumerState<_StationPage> createState() => _StationPageState();
}

class _StationPageState extends ConsumerState<_StationPage> {
  /// How long the pass takes on screen.
  static const _run = Duration(seconds: 9);
  late final DateTime _opened = onboardingClock();
  bool _caught = false;
  SkyEvent? _pass;
  bool _practice = false;

  /// The sky's moment: the pass from its start, sped up so it takes [_run],
  /// round again after a short pause.
  DateTime _clock() {
    final e = _pass!;
    final span = e.end.difference(e.start);
    final loop = _run + const Duration(milliseconds: 900);
    final into = onboardingClock().difference(_opened).inMicroseconds % loop.inMicroseconds;
    final k = (into / _run.inMicroseconds).clamp(0.0, 1.0);
    return e.start.add(Duration(microseconds: (span.inMicroseconds * k).round()));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider).value;
    final home = ref.watch(homeProvider).value;
    final lat = s?.latitude ?? 0, lon = s?.longitude ?? 0;
    if (_pass == null) {
      final real = passToPreview(home?.events ?? const [], _opened);
      _practice = real == null;
      // A practice pass: a smooth arc across the south, six minutes long.
      _pass = real ??
          SkyEvent(
            id: 'practice-pass',
            type: SkyEventType.iss,
            start: _opened.toUtc(),
            peak: _opened.toUtc().add(const Duration(minutes: 3)),
            end: _opened.toUtc().add(const Duration(minutes: 6)),
            peakElevationDeg: 55,
            riseAzimuthDeg: 250,
            peakAzimuthDeg: 180,
            setAzimuthDeg: 110,
          );
    }
    final e = _pass!;
    final speed = (e.end.difference(e.start).inMilliseconds / _run.inMilliseconds).round();
    final view = SkyDir(e.peakAzimuthDeg, (e.peakElevationDeg * 0.6).clamp(25.0, 45.0));
    final caughtFact = 'About 28,000 km/h, 400 km up: round the Earth every 90 minutes, which is why it passes over you so often.';
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Positioned.fill(
          child: FirstLookSky(
            key: const Key('station-preview'),
            things: const [],
            tracks: [passTrack(e, lat, lon)],
            lat: lat,
            lon: lon,
            catalog: ref.watch(skyCatalogProvider).value,
            clock: _clock,
            lockedTo: view,
            leadId: e.id,
            enabled: !_caught,
            onCatch: (_, _) => setState(() => _caught = true),
          ),
        ),
        Positioned.fill(child: _Flash(on: _caught)),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (!_caught)
                StreamBuilder<int>(
                  stream: Stream.periodic(const Duration(milliseconds: 250), (i) => i),
                  builder: (context, _) => _SkyWords(
                    _practice ? 'A practice pass' : '${fmtDay(e.start)}, ${fmtTime(_clock())}',
                    sub: _practice ? 'Sped up $speed×' : 'The space station, sped up $speed×',
                    key: const Key('station-clock'),
                  ),
                ),
              const Spacer(),
              if (_caught)
                _CaughtCard(
                  kicker: _practice ? 'Practice catch' : 'Preview catch · ${fmtDay(e.start)}, ${fmtTime(e.start)}',
                  title: 'You caught the space station',
                  fact: _practice ? caughtFact : '$caughtFact The real one is ${fmtDay(e.start).toLowerCase()} at ${fmtTime(e.start)}.',
                  onNext: widget.onNext,
                )
              else ...[
                const _SkyWords('Some things don\'t wait.', sub: 'Tap Pip while it rides the station.'),
                if (home?.approximate ?? false)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Times may be off by a few minutes until we can reach the satellite tracker.',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: LookUpColors.greyDim)),
                  ),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Moment 6: why passes come at dusk and dawn, by sliding through a day.
class _WhyPage extends StatefulWidget {
  const _WhyPage({required this.onNext});
  final VoidCallback onNext;
  @override
  State<_WhyPage> createState() => _WhyPageState();
}

class _WhyPageState extends State<_WhyPage> {
  bool _found = false;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SkyBackdrop(
          child: SafeArea(
            child: _FillOrScroll(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Kicker('Why only at dusk and dawn?'),
                const SizedBox(height: 8),
                Text('It has no lights of its own.', style: display(28, weight: FontWeight.w700, height: 1.1)),
                const SizedBox(height: 8),
                const Text('Slide through the day until the station shows up over you.', style: TextStyle(color: LookUpColors.grey, height: 1.4)),
                const SizedBox(height: 16),
                TwilightSlider(onFound: () => setState(() => _found = true)),
                const SizedBox(height: 12),
                if (_found)
                  const Rise(
                    index: 0,
                    child: Text(
                      'That\'s why. It shines with sunlight, so you need a dark sky while it\'s still up in the sun: the hours after sunset and before sunrise. That\'s when every station alert comes.',
                      key: Key('twilight-why'),
                      style: TextStyle(height: 1.45),
                    ),
                  ),
                const Spacer(),
                FilledButton(onPressed: widget.onNext, child: Text(_found ? 'Next' : 'Skip')),
              ]),
            ),
          ),
        ),
      );
}

/// Moment 7: what Pip should tell them about. Each switch is the setting
/// itself (Settings → What to tell me about), saved as it's flipped.
class _PickPage extends ConsumerWidget {
  const _PickPage({required this.onNext});
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider).value ?? const LookUpSettings();
    void set(LookUpSettings Function(LookUpSettings) f) => ref.read(settingsProvider.notifier).edit(f);
    final rows = <({String key, IconData icon, Color color, String title, String line, bool plus, bool on, void Function(bool) flip})>[
      (key: 'iss', icon: Icons.satellite_alt_rounded, color: LookUpColors.blue, title: 'The space station', line: 'A few times a week', plus: false, on: s.issEnabled, flip: (v) => set((x) => x.copyWith(issEnabled: v))),
      (key: 'meteors', icon: Icons.auto_awesome_rounded, color: LookUpColors.orange, title: 'Meteor showers', line: 'The best nights of each', plus: false, on: s.meteorsEnabled, flip: (v) => set((x) => x.copyWith(meteorsEnabled: v))),
      (key: 'moon', icon: Icons.nightlight_round, color: LookUpColors.cyan, title: 'Eclipses and the Moon', line: 'Full Moons rising, eclipses', plus: false, on: s.eclipsesEnabled && s.moonriseEnabled, flip: (v) => set((x) => x.copyWith(eclipsesEnabled: v, moonriseEnabled: v))),
      (key: 'planets', icon: Icons.blur_on_rounded, color: LookUpColors.gold, title: 'Planets meeting', line: 'Close pairs in the twilight', plus: false, on: s.pairingsEnabled, flip: (v) => set((x) => x.copyWith(pairingsEnabled: v))),
      (key: 'starlink', icon: Icons.linear_scale_rounded, color: LookUpColors.violet, title: 'Starlink trains', line: 'After each launch', plus: true, on: s.starlinkEnabled, flip: (v) => set((x) => x.copyWith(starlinkEnabled: v))),
      (key: 'aurora', icon: Icons.waves_rounded, color: LookUpColors.good, title: 'Aurora', line: 'The moment it\'s visible from here', plus: true, on: s.auroraEnabled, flip: (v) => set((x) => x.copyWith(auroraEnabled: v))),
    ];
    final plusOn = !s.isPlus && rows.any((r) => r.plus && r.on);
    return Scaffold(
      body: SkyBackdrop(
        child: SafeArea(
          child: _FillOrScroll(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Center(child: PipMark(size: 72)),
              const SizedBox(height: 4),
              const Kicker('Pip will watch for…', color: LookUpColors.good),
              const SizedBox(height: 8),
              Text('What should Pip tell you about?', style: display(28, weight: FontWeight.w700, height: 1.1)),
              const SizedBox(height: 14),
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Pressable(
                    key: Key('pick-${r.key}'),
                    semanticLabel: '${r.title}${r.plus ? ', LookUp+' : ''}, ${r.on ? 'on' : 'off'}',
                    onTap: () => r.flip(!r.on),
                    child: GlassCard(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Row(children: [
                        EventGlyph(icon: r.icon, color: r.color, size: 36),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(r.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                            Text(r.line, style: const TextStyle(fontSize: 12.5, color: LookUpColors.grey)),
                          ]),
                        ),
                        Pill(r.plus ? 'LookUp+' : 'Free', color: r.plus ? LookUpColors.blue : LookUpColors.good),
                        const SizedBox(width: 6),
                        ExcludeSemantics(child: Switch(value: r.on, onChanged: r.flip)),
                      ]),
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                plusOn ? 'The LookUp+ ones come with a 7-day free trial at the end.' : 'You can change these any time in Settings.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, color: LookUpColors.greyDim),
              ),
              const Spacer(),
              const SizedBox(height: 12),
              FilledButton(onPressed: onNext, child: const Text('Next')),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A full-height page whose spacers share out the room on a tall phone,
/// and which scrolls instead of overflowing on a short one.
class _FillOrScroll extends StatelessWidget {
  const _FillOrScroll({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight - 40),
            child: IntrinsicHeight(child: child),
          ),
        ),
      );
}


/// Moment 3: the one ask, with the tap it buys shown first.
class _AskPage extends ConsumerWidget {
  const _AskPage({required this.busy, required this.onFinish});
  final bool busy;
  final Future<void> Function({required bool alerts}) onFinish;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider).value;
    final lead = s?.leadMinutes ?? 10;
    final now = DateTime.now().toUtc();
    final first = [
      for (final e in ref.watch(homeProvider).value?.events ?? const <SkyEvent>[])
        if (e.type.pushes && !e.plusOnly && e.start.isAfter(now)) e,
    ].firstOrNull;
    final title = first == null ? 'Something bright is coming' : eventTitle(first);
    return Scaffold(
      body: SkyBackdrop(
        child: SafeArea(
          child: _FillOrScroll(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Spacer(),
              Rise(index: 0, child: const Kicker('One tap', color: LookUpColors.blue)),
              const SizedBox(height: 10),
              Rise(
                index: 1,
                child: Text('Then we\'ll tap you $lead minutes before.',
                    style: display(32, weight: FontWeight.w700, height: 1.1)),
              ),
              const SizedBox(height: 20),
              // What the tap will look like.
              Rise(
                index: 2,
                child: GlassCard(
                  key: const Key('tap-preview'),
                  padding: const EdgeInsets.all(14),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const PipMark(key: Key('onboarding-pip-blink'), size: 34, blinking: true),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('LookUp · now', style: const TextStyle(fontSize: 12, color: LookUpColors.grey)),
                        const SizedBox(height: 2),
                        Text('$title in $lead min',
                            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        const Text('Face south-west and look up. Clear skies.',
                            style: TextStyle(fontSize: 13.5, color: LookUpColors.grey, height: 1.3)),
                      ]),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'These last a few minutes, so they\'re easy to miss. LookUp stays quiet when it\'s cloudy.',
                style: TextStyle(color: LookUpColors.grey, height: 1.45),
              ),
              const Spacer(flex: 2),
              FilledButton.icon(
                onPressed: busy ? null : () => onFinish(alerts: true),
                icon: const Icon(Icons.notifications_active_rounded),
                label: Text('Tap me $lead minutes before'),
              ),
              TextButton(
                onPressed: busy ? null : () => onFinish(alerts: false),
                child: const Text('Not now'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}


/// The one-time LookUp+ offer at the end of setting up: the real taps it
/// would send over them this month (or, before those are known, what it
/// adds), a 7-day trial, and a plain "Not now". Never again after this.
class _OfferPage extends ConsumerWidget {
  const _OfferPage({required this.onTry, required this.onNotNow});
  final VoidCallback onTry, onNotNow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = PlusPreview.of(ref.watch(homeProvider).value?.events ?? const <SkyEvent>[], DateTime.now());
    return Scaffold(
      body: SkyBackdrop(
        child: SafeArea(
          child: _FillOrScroll(
            child: Column(key: const Key('trial-offer'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Spacer(),
              const Center(child: PipMark(size: 72)),
              const SizedBox(height: 6),
              Rise(index: 0, child: const Kicker('LookUp+', color: LookUpColors.blue)),
              const SizedBox(height: 10),
              Rise(
                index: 1,
                child: Text(
                  p.count == 0 ? 'Want a tap for everything up there?' : 'There\'s more coming over you',
                  style: display(32, weight: FontWeight.w700, height: 1.1),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                p.count == 0
                    ? 'Free taps you for the space station, meteor showers and eclipses. LookUp+ adds the rest.'
                    : 'Free taps you for the space station. ${p.count == 1 ? 'Here\'s one' : 'Here are ${p.count}'} it won\'t, this month:',
                style: const TextStyle(color: LookUpColors.grey, height: 1.45),
              ),
              const SizedBox(height: 16),
              Rise(
                index: 2,
                child: GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Column(children: [
                    if (p.count > 0)
                      for (final e in p.soonest)
                        _OfferRow(glyph: EventGlyph.of(e, size: 34), title: eventTitle(e), line: '${fmtDay(e.start)}, ${fmtTime(e.start)}')
                    else ...[
                      _OfferRow(
                          glyph: const EventGlyph(icon: Icons.waves_rounded, color: LookUpColors.good, size: 34),
                          title: 'Aurora, the moment it\'s visible',
                          line: 'Live alerts from here, not a forecast'),
                      _OfferRow(
                          glyph: const EventGlyph(icon: Icons.linear_scale_rounded, color: LookUpColors.violet, size: 34),
                          title: 'Starlink trains and Tiangong',
                          line: 'A tap before each one goes over'),
                      _OfferRow(
                          glyph: const EventGlyph(icon: Icons.near_me_rounded, color: LookUpColors.blue, size: 34),
                          title: 'Where to go tonight',
                          line: 'Clearer, darker skies near you'),
                    ],
                  ]),
                ),
              ),
              const Spacer(flex: 2),
              FilledButton(
                key: const Key('trial-offer-try'),
                onPressed: onTry,
                child: const Text('Try 7 days free'),
              ),
              TextButton(key: const Key('trial-offer-not-now'), onPressed: onNotNow, child: const Text('Not now')),
            ]),
          ),
        ),
      ),
    );
  }
}


class _OfferRow extends StatelessWidget {
  const _OfferRow({required this.glyph, required this.title, required this.line});
  final Widget glyph;
  final String title, line;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          glyph,
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              Text(line, style: const TextStyle(fontSize: 13, color: LookUpColors.grey)),
            ]),
          ),
          const Icon(Icons.notifications_active_outlined, size: 18, color: LookUpColors.blue),
        ]),
      );
}
