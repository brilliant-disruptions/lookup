import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/finder/pointing.dart' show SkyDir;
import '../domain/models/settings.dart';
import '../domain/models/sky_event.dart';
import '../domain/onboarding/first_look.dart';
import '../domain/plus/plus_preview.dart';
import '../domain/scheduling/alert_planner.dart';
import '../domain/sky/catalog.dart';
import '../services/plus_service.dart';
import '../state/providers.dart';
import '../state/sky_state.dart';
import 'format.dart';
import 'help.dart';
import 'kit/kit.dart';
import 'onboarding/first_look_sky.dart';
import 'onboarding/light_up.dart';
import 'onboarding/offer_sky.dart';
import 'onboarding/twilight_slider.dart';
import 'paywall_sheet.dart';
import 'places_screen.dart';
import 'plus_perks.dart';
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
  const OnboardingScreen({super.key, this.preview = false});

  /// Replaying the intro from Settings (`openIntroPreview`): nothing sticks.
  /// No permission prompts, no refresh, no paywall; choices go into a
  /// throwaway copy of the settings; the end just closes it.
  final bool preview;
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
    // (A preview uses what's already there.)
    if (!widget.preview) unawaited(ref.read(refreshServiceProvider).prefetch().catchError((_) {}));
  }

  void _go(_Step s) => setState(() => _step = s);

  Future<void> _showMe() async {
    if (widget.preview) {
      // Their place is already known: no prompt, straight to their sky.
      final s = await ref.read(settingsProvider.future);
      if (!mounted) return;
      return s.hasLocation ? _look() : _go(_Step.noLocation);
    }
    setState(() => _busy = true);
    final ok = await ref.read(locationServiceProvider).requestPermission();
    if (!mounted) return;
    setState(() => _busy = false);
    ok ? await _look() : _go(_Step.noLocation);
  }

  Future<void> _pickTown() async {
    if (widget.preview) return _look();
    await openPlaces(context);
    if (!mounted) return;
    final s = await ref.read(settingsProvider.future);
    if (s.hasLocation) await _look();
  }

  /// The first refresh, while the globe turns, so the sky and the pass that
  /// follow are theirs. Quick first (location and the ISS only); clouds,
  /// aurora and Starlink follow in the background.
  /// Done when Pip has lit up their sky (or there was nothing to light).
  Completer<void> _litUp = Completer<void>();

  Future<void> _look() async {
    _litUp = Completer<void>();
    _go(_Step.looking);
    final started = onboardingClock();
    try {
      // Let the stored (empty) data finish loading first, or it can land
      // after the refresh and hide what it found.
      await ref.read(homeProvider.future);
      // A preview shows the sky they already have; no refresh, nothing saved.
      if (!widget.preview) await ref.read(homeProvider.notifier).refresh(quick: true);
    } catch (_) {
      // Offline: the pages after this say so, and the shell retries.
    }
    if (!widget.preview) unawaited(ref.read(homeProvider.notifier).refresh().catchError((_) {}));
    if (!mounted || _step != _Step.looking) return;
    // Allowed, but no fix came (indoors, airplane mode): a town instead of a wait.
    final s = await ref.read(settingsProvider.future);
    if (!mounted) return;
    if (!s.hasLocation) return _go(_Step.noLocation);
    // Let Pip finish lighting up their sky; never more than about four seconds.
    final left = const Duration(seconds: 4) - onboardingClock().difference(started);
    final cap = Timer(left.isNegative ? Duration.zero : left, () {
      if (!_litUp.isCompleted) _litUp.complete();
    });
    await _litUp.future;
    cap.cancel();
    if (mounted && _step == _Step.looking) _go(_Step.sky);
  }

  Future<void> _finish({required bool alerts}) async {
    setState(() => _busy = true);
    if (alerts && !widget.preview) {
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
    if (widget.preview || (!s.isPlus && !s.trialOfferShown)) {
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

  Future<void> _done() async {
    if (widget.preview) {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    await ref
        .read(settingsProvider.notifier)
        .edit((s) => s.copyWith(onboarded: true, onboardedAt: DateTime.now().toUtc(), trialOfferShown: true));
  }

  /// The offer's two ways out: a trial (through the paywall), or "Not now",
  /// which counts as a decline for the soft asks (domain/plus/nudges.dart).
  Future<void> _offer({required bool tryIt}) async {
    // A preview never sells or counts a decline: either way out just ends it.
    if (widget.preview) return _done();
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
  Widget build(BuildContext context) {
    final page = _page();
    if (!widget.preview) return page;
    // The preview says so, and can be left from any page.
    return Stack(children: [
      page,
      Positioned(
        top: MediaQuery.paddingOf(context).top + 8,
        left: 16,
        right: 12,
        child: Row(children: [
          const Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(fit: BoxFit.scaleDown, child: Pill('Preview · nothing is saved', color: LookUpColors.blue)),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            key: const Key('intro-preview-close'),
            tooltip: 'Close the preview',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ]),
      ),
    ]);
  }

  Widget _page() => switch (_step) {
        _Step.wake => _WakePage(onWake: () => _go(_Step.hello)),
        _Step.hello || _Step.noLocation => _HelloPage(
            busy: _busy,
            denied: _step == _Step.noLocation,
            onShowMe: _showMe,
            onTown: _pickTown,
          ),
        _Step.looking => _LookingPage(onDone: () {
            if (!_litUp.isCompleted) _litUp.complete();
          }),
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
                const Center(child: PipMark(key: Key('onboarding-pip'), size: 150, state: PipState.greet, mood: PipMood.curious)),
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

/// Moment 3: while LookUp works out their sky, Pip lights it up: the real
/// stars over their place fly out to where they sit and the horizon rises
/// with the place's name on it. Its last frame is the next page's first.
class _LookingPage extends ConsumerStatefulWidget {
  const _LookingPage({required this.onDone});
  final VoidCallback onDone;
  @override
  ConsumerState<_LookingPage> createState() => _LookingPageState();
}

class _LookingPageState extends ConsumerState<_LookingPage> {
  late final DateTime _opened = onboardingClock();
  bool _gaveUp = false;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider).value;
    final catalog = ref.watch(skyCatalogProvider);
    final look = ref.watch(firstLookProvider);
    final lat = s?.latitude, lon = s?.longitude;
    final ready = lat != null && lon != null && catalog.hasValue && !look.isLoading;
    // No stars to light (no catalog, no sky): don't hold them up.
    if (!_gaveUp && (catalog.hasError || look.hasError || (lat != null && !look.isLoading && look.value == null))) {
      _gaveUp = true;
      Future<void>.delayed(const Duration(milliseconds: 900), widget.onDone);
    }
    final place = (s?.placeName?.isNotEmpty ?? false) ? s!.placeName! : null;
    return Scaffold(
      backgroundColor: const Color(0xFF03050C),
      body: Stack(children: [
        Positioned.fill(
          child: ready
              ? LightUpSky(
                  key: const Key('onboarding-light-up'),
                  catalog: catalog.value!,
                  lat: lat,
                  lon: lon,
                  at: firstLookTime(_opened, look.value?.window).at,
                  look: firstLookStart,
                  place: place,
                  onDone: widget.onDone,
                )
              : const SkyBackdrop(child: Center(child: PipMark(size: 60, state: PipState.searching, mood: PipMood.focused))),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Align(
              alignment: Alignment.topCenter,
              child: const _SkyWords('Lighting up your sky…'),
            ),
          ),
        ),
      ]),
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
      return const Scaffold(body: SkyBackdrop(child: Center(child: PipMark(size: 60, state: PipState.searching, mood: PipMood.focused))));
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
/// itself (Settings → What to tell me about), saved as it's flipped. No
/// prices here: which of these are LookUp+ is said once, on the offer.
class _PickPage extends ConsumerWidget {
  const _PickPage({required this.onNext});
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider).value ?? const LookUpSettings();
    void set(LookUpSettings Function(LookUpSettings) f) => ref.read(settingsProvider.notifier).edit(f);
    final rows = <({String key, IconData icon, Color color, String title, String line, bool on, void Function(bool) flip})>[
      (key: 'iss', icon: Icons.satellite_alt_rounded, color: LookUpColors.blue, title: 'The space station', line: 'A few times a week', on: s.issEnabled, flip: (v) => set((x) => x.copyWith(issEnabled: v))),
      (key: 'meteors', icon: Icons.auto_awesome_rounded, color: LookUpColors.orange, title: 'Meteor showers', line: 'The best nights of each', on: s.meteorsEnabled, flip: (v) => set((x) => x.copyWith(meteorsEnabled: v))),
      (key: 'moon', icon: Icons.nightlight_round, color: LookUpColors.cyan, title: 'Eclipses and the Moon', line: 'Full Moons rising, eclipses', on: s.eclipsesEnabled && s.moonriseEnabled, flip: (v) => set((x) => x.copyWith(eclipsesEnabled: v, moonriseEnabled: v))),
      (key: 'planets', icon: Icons.blur_on_rounded, color: LookUpColors.gold, title: 'Planets meeting', line: 'Close pairs in the twilight', on: s.pairingsEnabled, flip: (v) => set((x) => x.copyWith(pairingsEnabled: v))),
      (key: 'starlink', icon: Icons.linear_scale_rounded, color: LookUpColors.violet, title: 'Starlink trains', line: 'After each launch', on: s.starlinkEnabled, flip: (v) => set((x) => x.copyWith(starlinkEnabled: v))),
      (key: 'aurora', icon: Icons.waves_rounded, color: LookUpColors.good, title: 'Aurora', line: 'The moment it\'s visible from here', on: s.auroraEnabled, flip: (v) => set((x) => x.copyWith(auroraEnabled: v))),
    ];
    return Scaffold(
      body: SkyBackdrop(
        child: SafeArea(
          child: _FillOrScroll(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Center(child: PipMark(size: 72, mood: PipMood.happy)),
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
                    semanticLabel: '${r.title}, ${r.on ? 'on' : 'off'}',
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
                        ExcludeSemantics(child: Switch(value: r.on, onChanged: r.flip)),
                      ]),
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              const Text('You can change these any time in Settings.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: LookUpColors.greyDim)),
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
                    const PipMark(key: Key('onboarding-pip-blink'), size: 34, blinking: true, mood: PipMood.shy),
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


/// The one-time LookUp+ offer at the end of setting up: "Light up your sky".
/// Their sky from the sky page comes back dimmed, and each LookUp+ thing is
/// a switch that turns it on in that sky while Pip flies over to it. Aurora
/// and Starlink (only if left on) also drop in the tap they'd get, from a
/// real one coming when there is one. Then the real sights coming, the rest
/// of LookUp+, a 7-day trial and a plain "Not now". Never again after this.
/// The yearly plan's price as the store shows it (null until known).
final _yearlyPrice = FutureProvider.autoDispose<String?>((ref) async {
  try {
    final offers = await ref.watch(plusServiceProvider).offers();
    return offers.where((o) => o.id == PlusProducts.yearly).firstOrNull?.price;
  } catch (_) {
    return null;
  }
});

class _OfferPage extends ConsumerStatefulWidget {
  const _OfferPage({required this.onTry, required this.onNotNow});
  final VoidCallback onTry, onNotNow;

  @override
  ConsumerState<_OfferPage> createState() => _OfferPageState();
}

typedef _Light = ({OfferLight light, String key, String name, String line, Color color});

const _lights = <_Light>[
  (light: OfferLight.aurora, key: 'aurora', name: 'Aurora', line: 'The moment it\'s visible here', color: LookUpColors.good),
  (light: OfferLight.starlink, key: 'starlink', name: 'Starlink trains', line: 'A tap before each one', color: LookUpColors.violet),
  (light: OfferLight.darker, key: 'darker', name: 'Darker skies', line: 'Where to go tonight', color: LookUpColors.blue),
  (light: OfferLight.timelapse, key: 'timelapse', name: 'Timelapses', line: 'Start and stop themselves', color: LookUpColors.cyan),
  (light: OfferLight.camera, key: 'camera', name: 'Pro camera', line: 'The sharpest of 40', color: LookUpColors.gold),
];

class _OfferPageState extends ConsumerState<_OfferPage> {
  final _lit = <OfferLight>{};
  OfferLight? _last;
  late final DateTime _opened = onboardingClock();

  /// The tap shown at the top: (title, body, when).
  ({String title, String body, String when})? _tap;
  Timer? _tapTimer;

  @override
  void dispose() {
    _tapTimer?.cancel();
    super.dispose();
  }

  void _flip(OfferLight l, PlusPreview p, LookUpSettings? s) {
    setState(() {
      if (!_lit.remove(l)) {
        _lit.add(l);
        _last = l;
        _tap = _tapFor(l, p, s);
      } else if (_last == l) {
        _last = null;
      }
    });
    if (_tap != null) {
      _tapTimer?.cancel();
      _tapTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _tap = null);
      });
    }
  }

  /// What the alert would say: the real coming one if there is one.
  ({String title, String body, String when})? _tapFor(OfferLight l, PlusPreview p, LookUpSettings? s) {
    final type = switch (l) {
      OfferLight.aurora => SkyEventType.auroraNow,
      OfferLight.starlink => SkyEventType.starlinkTrain,
      _ => null,
    };
    if (type == null) return null;
    final e = p.soonest.where((e) => e.type == type).firstOrNull;
    if (e != null) {
      final title = type == SkyEventType.auroraNow ? AlertPlanner.auroraNowTitle(e) : AlertPlanner.headsUpTitle(e, 10);
      return (title: title, body: AlertPlanner.headsUpBody(e, miles: s?.usesMiles ?? false), when: '${fmtDay(e.start)}, ${fmtTime(e.start)}');
    }
    return type == SkyEventType.auroraNow
        ? (title: 'Aurora now', body: 'Find a dark spot and look north.', when: 'Example')
        : (title: 'Starlink train in 10 min', body: 'A line of lights, one after another.', when: 'Example');
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider).value;
    final p = PlusPreview.of(ref.watch(homeProvider).value?.events ?? const <SkyEvent>[], DateTime.now(), wants: s);
    final aurora = s?.auroraEnabled ?? false, starlink = s?.starlinkEnabled ?? false;
    // The kinds still switched on that free doesn't tap for. They may have
    // left them on rather than picked them, so the words never say "you
    // asked"; and a kind they turned off is never pitched.
    final picked = [if (aurora) 'aurora', if (starlink) 'Starlink trains'];
    final asked = picked.join(' and ');
    final lights = [
      for (final l in _lights)
        if ((l.light != OfferLight.aurora || aurora) && (l.light != OfferLight.starlink || starlink)) l,
    ];
    final on = lights.where((l) => _lit.contains(l.light)).length;
    final all = on == lights.length;
    final title = picked.isNotEmpty
        ? '${asked[0].toUpperCase()}${asked.substring(1)} ${picked.length == 1 && aurora ? 'is' : 'are'} LookUp+'
        : 'Want more from your sky?';
    final body = picked.isNotEmpty
        ? 'Pip\'s set to watch for $asked. Free taps you for the space station, meteor showers, eclipses and the Moon. Turn each one on and watch your sky.'
        : 'Free taps you for what you picked. Turn each one on and watch your sky.';
    final catalog = ref.watch(skyCatalogProvider).value;
    final at = firstLookTime(_opened, ref.watch(firstLookProvider).value?.window).at;
    return Scaffold(
      body: SkyBackdrop(
        child: SafeArea(
          child: Stack(children: [
            // The content scrolls; the two buttons stay put at the bottom.
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 12),
                  child: Column(key: const Key('trial-offer'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Rise(index: 0, child: const Kicker('LookUp+', color: LookUpColors.blue)),
                    const SizedBox(height: 10),
                    Rise(
                      index: 1,
                      child: Text(title, key: const Key('trial-offer-title'), style: display(30, weight: FontWeight.w700, height: 1.1)),
                    ),
                    const SizedBox(height: 8),
                    Text(body, key: const Key('trial-offer-body'), style: const TextStyle(color: LookUpColors.grey, height: 1.45)),
                    const SizedBox(height: 14),
                    Rise(
                      index: 2,
                      child: SizedBox(
                        height: 230,
                        child: OfferSky(
                          catalog: catalog ?? SkyCatalog.empty,
                          lat: s?.latitude ?? 0,
                          lon: s?.longitude ?? 0,
                          at: at,
                          lit: Set.of(_lit),
                          last: _last,
                          place: s?.placeName,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _Meter(on: on, of: lights.length),
                    const SizedBox(height: 10),
                    _LightGrid(
                      lights: lights,
                      lit: _lit,
                      onFlip: (l) => _flip(l, p, s),
                    ),
                    if (p.count > 0) ...[
                      const SizedBox(height: 18),
                      Kicker(p.count == 1 ? 'Coming over you' : '${p.count} coming over you this month'),
                      const SizedBox(height: 8),
                      GlassCard(
                        key: const Key('trial-offer-sights'),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        child: Column(children: [
                          for (final e in p.soonest)
                            _OfferRow(glyph: EventGlyph.of(e, size: 34), title: eventTitle(e), line: '${fmtDay(e.start)}, ${fmtTime(e.start)}'),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 18),
                    const Kicker('Also with LookUp+'),
                    const SizedBox(height: 8),
                    PlusPerkGrid(
                      key: const Key('trial-offer-perks'),
                      except: {'camera', 'timelapse', 'whereToGo', if (picked.isNotEmpty) 'alerts'},
                    ),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Radii.md),
                      boxShadow: [if (all) BoxShadow(color: LookUpColors.blue.withValues(alpha: 0.45), blurRadius: 22)],
                    ),
                    child: FilledButton(
                      key: const Key('trial-offer-try'),
                      onPressed: widget.onTry,
                      child: Text(all ? 'Keep it all on: 7 days free' : 'Try 7 days free'),
                    ),
                  ),
                  TextButton(key: const Key('trial-offer-not-now'), onPressed: widget.onNotNow, child: const Text('Not now')),
                  Text(
                    // The store's own price for their country, when it's known.
                    switch (ref.watch(_yearlyPrice).value) {
                      final price? => '7 days free, then $price a year, renewing until you cancel. Pip reminds you before the trial ends.',
                      null => '7 days free on the yearly plan, then it renews each year until you cancel. Pip reminds you before the trial ends.',
                    },
                    key: const Key('trial-offer-terms'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11.5, color: LookUpColors.greyDim),
                  ),
                  const LegalLinks(),
                ]),
              ),
            ]),
            // The tap they'd get, dropping in from the top.
            Positioned(
              left: 10,
              right: 10,
              top: 6,
              child: IgnorePointer(
                child: AnimatedSlide(
                  offset: _tap == null ? const Offset(0, -1.6) : Offset.zero,
                  duration: const Duration(milliseconds: 420),
                  curve: _tap == null ? Curves.easeIn : Curves.easeOutBack,
                  child: _tap == null ? const SizedBox(height: 64) : _TapPreview(tap: _tap!),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Meter extends StatelessWidget {
  const _Meter({required this.on, required this.of});
  final int on, of;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Stack(children: [
              Container(height: 5, color: LookUpColors.glassStrong),
              AnimatedFractionallySizedBox(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                widthFactor: of == 0 ? 0 : on / of,
                child: Container(
                  height: 5,
                  decoration: const BoxDecoration(gradient: LinearGradient(colors: [fireflyGlow, LookUpColors.good])),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 10),
        Text('$on of $of on', key: const Key('offer-lit-count'), style: const TextStyle(fontSize: 12.5, color: LookUpColors.grey)),
      ]);
}

/// The switches, two to a row.
class _LightGrid extends StatelessWidget {
  const _LightGrid({required this.lights, required this.lit, required this.onFlip});
  final List<_Light> lights;
  final Set<OfferLight> lit;
  final ValueChanged<OfferLight> onFlip;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < lights.length; i += 2) {
      rows.add(IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _LightTile(light: lights[i], on: lit.contains(lights[i].light), onTap: () => onFlip(lights[i].light))),
          const SizedBox(width: 8),
          Expanded(
            child: i + 1 < lights.length
                ? _LightTile(light: lights[i + 1], on: lit.contains(lights[i + 1].light), onTap: () => onFlip(lights[i + 1].light))
                : const SizedBox(),
          ),
        ]),
      ));
      if (i + 2 < lights.length) rows.add(const SizedBox(height: 8));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

class _LightTile extends StatelessWidget {
  const _LightTile({required this.light, required this.on, required this.onTap});
  final _Light light;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        key: Key('offer-light-${light.key}'),
        onTap: onTap,
        semanticLabel: '${light.name}, ${on ? 'on' : 'off'}',
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          decoration: BoxDecoration(
            color: on ? light.color.withValues(alpha: 0.16) : LookUpColors.glass,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: on ? light.color.withValues(alpha: 0.6) : LookUpColors.line),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(light.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.2)),
                const SizedBox(height: 2),
                Text(light.line, style: const TextStyle(fontSize: 12, color: LookUpColors.grey, height: 1.25)),
              ]),
            ),
            const SizedBox(width: 6),
            _Toggle(on: on, color: light.color),
          ]),
        ),
      );
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.on, required this.color});
  final bool on;
  final Color color;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 30,
        height: 18,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(color: on ? color : LookUpColors.glassStrong, borderRadius: BorderRadius.circular(9)),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(width: 14, height: 14, decoration: const BoxDecoration(color: LookUpColors.white, shape: BoxShape.circle)),
        ),
      );
}

/// A Lock Screen banner: the tap LookUp+ would send.
class _TapPreview extends StatelessWidget {
  const _TapPreview({required this.tap});
  final ({String title, String body, String when}) tap;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('offer-tap-preview'),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: LookUpColors.panelRaised,
          border: Border.all(color: LookUpColors.line),
          borderRadius: BorderRadius.circular(Radii.lg),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 8))],
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: LookUpColors.night, borderRadius: BorderRadius.circular(9)),
            child: const Center(child: PipMark(size: 26)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tap.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(tap.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: LookUpColors.white, height: 1.3)),
              const SizedBox(height: 3),
              Text(tap.when, style: const TextStyle(fontSize: 11.5, color: LookUpColors.grey)),
            ]),
          ),
        ]),
      );
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

/// Settings for the intro preview: a copy of theirs that takes the intro's
/// choices and forgets them when it closes.
class _PreviewSettings extends SettingsNotifier {
  _PreviewSettings(this.start);
  final LookUpSettings start;
  @override
  Future<LookUpSettings> build() async => start;
  @override
  Future<void> edit(LookUpSettings Function(LookUpSettings) f) async => state = AsyncData(f(state.value ?? start));
}

/// Replays the intro, as someone new would see it (the offer included),
/// with nothing saved: their settings, Log and LookUp+ are left as they are.
Future<void> openIntroPreview(BuildContext context, WidgetRef ref) async {
  final real = await ref.read(settingsProvider.future).catchError((_) => const LookUpSettings());
  if (!context.mounted) return;
  final copy = real.copyWith(isPlus: false, trialOfferShown: false);
  await Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => ProviderScope(
      overrides: [settingsProvider.overrideWith(() => _PreviewSettings(copy))],
      child: const OnboardingScreen(preview: true),
    ),
  ));
}

