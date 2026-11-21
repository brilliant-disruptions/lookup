import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/services/refresh_service.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/services/location_service.dart';
import 'package:lookup/services/notification_service.dart';
import 'package:lookup/services/plus_service.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/state/sky_state.dart' show skyCatalogProvider;
import 'package:lookup/ui/kit/kit.dart';
import 'package:lookup/ui/onboarding_screen.dart';
import 'package:lookup/ui/onboarding/first_look_sky.dart' show firstLookProvider;
import 'package:lookup/ui/paywall_sheet.dart';
import 'package:lookup/ui/sky/sky_thing.dart';
import 'package:lookup/domain/sky/astro.dart' show Horizontal;
import 'package:lookup/ui/theme.dart';

/// What settings start as; the offer tests change it.
/// What settings start as; the offer tests change it. The location is
/// what the phone's fix would have saved.
const _here = LookUpSettings(latitude: 36.17, longitude: -86.78, placeName: 'Nashville');
var _start = _here;

class _Settings extends SettingsNotifier {
  @override
  Future<LookUpSettings> build() async => _start;
  @override
  Future<void> edit(LookUpSettings Function(LookUpSettings) f) async =>
      state = AsyncData(f(state.value ?? await future));
}

final _now = DateTime.now().toUtc();

SkyEvent _ev(String id, SkyEventType type, Duration inFuture) => SkyEvent(
      id: id,
      type: type,
      start: _now.add(inFuture),
      peak: _now.add(inFuture + const Duration(minutes: 2)),
      end: _now.add(inFuture + const Duration(minutes: 5)),
      peakElevationDeg: 60,
      riseAzimuthDeg: 247,
      peakAzimuthDeg: 180,
      setAzimuthDeg: 90,
      details: const {'brightness': 'brighter than any star', 'label': 'Starlink train', 'count': 20},
    );

/// Nothing until the first refresh, as on a fresh install.
class _Home extends HomeNotifier {
  /// The `quick` flag of each refresh, in order.
  final quick = <bool>[];
  int get refreshes => quick.length;

  /// Holds full (not quick) refreshes until completed: Starlink on a slow network.
  Completer<void>? slowFull;

  /// Holds the quick look until completed: the ISS on a slow network.
  Completer<void>? slowQuick;

  /// Whether the look comes from the shipped ISS (Celestrak out of reach).
  bool approximate = false;

  /// Whether a space station pass is coming (false: a practice pass).
  bool passes = true;
  @override
  bool get refreshing => !(slowFull?.isCompleted ?? true);
  @override
  Future<HomeData> build() async => const HomeData(events: [], aurora: null, lastRefresh: null, errors: []);
  @override
  Future<void> refresh({bool force = false, bool quick = false}) async {
    this.quick.add(quick);
    if (!quick && slowFull != null) await slowFull!.future;
    if (quick && slowQuick != null) await slowQuick!.future;
    state = AsyncData(HomeData(
      events: [
        if (passes) _ev('iss:a', SkyEventType.iss, const Duration(hours: 5)),
        _ev('starlink:a', SkyEventType.starlinkTrain, const Duration(days: 1)), // Plus-only: no free tap
      ],
      aurora: null,
      lastRefresh: _now,
      errors: const [],
      approximate: approximate,
    ));
  }
}

class _Location implements LocationService {
  _Location(this.grant);
  final bool grant;
  int asked = 0;
  @override
  Future<bool> requestPermission() async {
    asked++;
    return grant;
  }
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Refresh implements RefreshService {
  int prefetched = 0;
  @override
  Future<void> prefetch() async => prefetched++;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakePlus implements PlusService {
  @override
  Stream<String> get errors => const Stream.empty();
  @override
  Future<List<PlusOffer>> offers() async => const [];
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Notifications implements NotificationService {
  int asked = 0;
  @override
  Future<bool> requestPermission() async {
    asked++;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}


/// Jupiter, up in the east-south-east: 60° left of where the sky starts.
final _jupiter = SkyThing(
  id: 'planet:jupiter',
  name: 'Jupiter',
  kind: 'Planet',
  position: (_) => const Horizontal(120, 30),
  mag: -2.5,
  finder: const {},
);

void main() {
  late ProviderContainer container;
  late _Home home;
  late _Notifications notifications;
  late _Refresh refresh;
  late _Location location;
  var clock = DateTime.now();
  setUp(() {
    clock = DateTime.now();
    onboardingClock = () => clock;
  });
  tearDown(() => onboardingClock = DateTime.now);

  Future<void> pump(WidgetTester t, {required bool grantLocation, List<SkyThing>? things, bool preview = false}) async {
    t.view.physicalSize = const Size(1179, 2556);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    home = _Home();
    notifications = _Notifications();
    refresh = _Refresh();
    container = ProviderContainer(overrides: [
      settingsProvider.overrideWith(_Settings.new),
      homeProvider.overrideWith(() => home),
      locationServiceProvider.overrideWithValue(location = _Location(grantLocation)),
      notificationServiceProvider.overrideWithValue(notifications),
      clockProvider.overrideWith((_) => Stream.value(DateTime.now())),
      plusServiceProvider.overrideWithValue(_FakePlus()),
      refreshServiceProvider.overrideWithValue(refresh),
      firstLookProvider.overrideWith((_) async => (things: things ?? [_jupiter], window: null)),
      skyCatalogProvider.overrideWith((_) async => throw 'no catalog in tests'),
    ]);
    addTearDown(container.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildLookUpTheme(),
        home: preview
            // Settings, with the Replay the intro row's own call behind a button.
            ? Consumer(builder: (context, ref, _) => Scaffold(body: Center(child: TextButton(onPressed: () => openIntroPreview(context, ref), child: const Text('Replay the intro')))))
            : const OnboardingScreen(),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> settle(WidgetTester t, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
  }

  /// Wake Pip and give the location: on to the sky (past the globe).
  Future<void> toSky(WidgetTester t) async {
    await t.tap(find.byKey(const Key('onboarding-wake')));
    await settle(t, 3);
    await t.tap(find.text('Show me my sky'));
    await settle(t, 9);
  }

  /// Drag the sky to Jupiter, let Pip land, and tap Pip.
  Future<void> catchJupiter(WidgetTester t) async {
    await t.drag(find.byKey(const Key('first-look')), const Offset(690, 0));
    await settle(t, 8);
    await t.tap(find.byKey(const Key('first-look-catch')));
    await settle(t, 3);
  }

  /// The station preview, half way through its sped-up run, caught.
  Future<void> catchStation(WidgetTester t) async {
    clock = clock.add(const Duration(milliseconds: 4500));
    await settle(t, 8);
    await t.tap(find.byKey(const Key('first-look-catch')));
    await settle(t, 3);
  }

  testWidgets('a faint light to tap; then Pip says hi and asks where you are, and why', (t) async {
    await pump(t, grantLocation: true);
    expect(find.text('Tap the light'), findsOneWidget);
    expect(t.widget<PipMark>(find.byKey(const Key('onboarding-pip'))).asDot, isTrue, reason: 'just a light, before it wakes');
    expect(refresh.prefetched, 1, reason: 'satellites load while Pip says hello');
    await t.tap(find.byKey(const Key('onboarding-wake')));
    await settle(t, 3);
    expect(t.widget<PipMark>(find.byKey(const Key('onboarding-pip'))).asDot, isFalse, reason: 'Pip, awake');
    expect(find.text('Hi. I find things in the sky for you.'), findsOneWidget);
    expect(find.text('Show me my sky'), findsOneWidget);
    expect(find.textContaining('never leaves your phone'), findsOneWidget);
    expect(notifications.asked, 0);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('your sky: the globe finds you, then drag to follow Pip to Jupiter and tap Pip to catch it', (t) async {
    await pump(t, grantLocation: true);
    await t.tap(find.byKey(const Key('onboarding-wake')));
    await settle(t, 3);
    await t.tap(find.text('Show me my sky'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Lighting up your sky…'), findsOneWidget);
    expect(home.quick.first, isTrue, reason: 'a quick look while the globe turns');
    await settle(t, 9);
    expect(find.byKey(const Key('first-look')), findsOneWidget);
    expect(find.text('Drag the sky. Follow Pip.'), findsOneWidget);
    expect(find.byKey(const Key('first-look-catch')), findsNothing, reason: 'Pip waits at the edge until Jupiter is in the middle');
    await t.drag(find.byKey(const Key('first-look')), const Offset(690, 0));
    await settle(t, 8);
    expect(find.text('That\'s Jupiter. Tap Pip to catch it!'), findsOneWidget);
    await t.tap(find.byKey(const Key('first-look-catch')));
    await settle(t, 3);
    expect(find.byKey(const Key('first-look-caught')), findsOneWidget);
    expect(find.text('You found Jupiter'), findsOneWidget);
    expect(find.textContaining('Practice catch'), findsOneWidget, reason: 'it says so: practice never goes in the Log');
    expect(find.textContaining('°'), findsNothing, reason: 'words, not degrees');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the station: tonight\'s real pass, sped up; Pip rides it and a tap catches the preview', (t) async {
    await pump(t, grantLocation: true);
    await toSky(t);
    await catchJupiter(t);
    await t.tap(find.text('Next'));
    await settle(t, 3);
    expect(find.byKey(const Key('station-preview')), findsOneWidget);
    expect(find.textContaining('The space station, sped up'), findsOneWidget, reason: 'the real ISS pass in 5 hours');
    await catchStation(t);
    expect(find.text('You caught the space station'), findsOneWidget);
    expect(find.textContaining('Preview catch'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('nothing bright up tonight: straight to a practice pass', (t) async {
    await pump(t, grantLocation: true, things: const []);
    home.passes = false;
    await toSky(t);
    expect(find.byKey(const Key('first-look')), findsNothing);
    expect(find.byKey(const Key('station-preview')), findsOneWidget);
    expect(find.text('A practice pass'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  /// From the start to the offer, turning off the switches named in [off]
  /// on the "What should Pip tell you about?" page.
  Future<void> toOffer(WidgetTester t, {Set<String> off = const {}}) async {
    await pump(t, grantLocation: true);
    await toSky(t);
    await catchJupiter(t);
    await t.tap(find.text('Next'));
    await settle(t, 3);
    await catchStation(t);
    await t.tap(find.text('Next'));
    await settle(t, 3);
    // Why: slide to the evening and it appears.
    expect(find.text('It has no lights of its own.'), findsOneWidget);
    expect(find.byKey(const Key('twilight-why')), findsNothing);
    t.widget<Slider>(find.byKey(const Key('twilight-slider'))).onChanged!(19);
    await settle(t, 2);
    expect(find.byKey(const Key('twilight-why')), findsOneWidget);
    await t.tap(find.text('Next'));
    await settle(t, 3);
    // What Pip tells you about: each switch is the setting, and no prices here.
    expect(find.text('What should Pip tell you about?'), findsOneWidget);
    expect(find.text('LookUp+'), findsNothing, reason: 'LookUp+ is said once, on the offer');
    expect(find.textContaining('free trial'), findsNothing);
    expect(container.read(settingsProvider).value!.auroraEnabled, isTrue);
    expect(container.read(settingsProvider).value!.starlinkEnabled, isTrue);
    for (final k in off) {
      await t.ensureVisible(find.byKey(Key('pick-$k')));
      await settle(t, 1);
      await t.tap(find.byKey(Key('pick-$k')));
      await settle(t, 1);
    }
    await t.ensureVisible(find.text('Next'));
    await t.tap(find.text('Next'));
    await settle(t, 3);
    // The ask, with the tap it buys shown first.
    expect(find.byKey(const Key('tap-preview')), findsOneWidget);
    expect(notifications.asked, 0);
    await t.tap(find.text('Tap me 10 minutes before'));
    await settle(t, 4);
    expect(notifications.asked, 1);
    // Once, the offer (not the paywall).
    expect(find.byKey(const Key('trial-offer')), findsOneWidget);
    expect(find.byType(PaywallSheet), findsNothing);
  }

  testWidgets('why dusk and dawn, what Pip tells you about, the alert ask, the offer: then done', (t) async {
    await toOffer(t, off: {'aurora'});
    expect(container.read(settingsProvider).value!.auroraEnabled, isFalse);
    // Built on what's on: aurora off, Starlink on, and the real train coming.
    expect(find.text('Starlink trains are LookUp+'), findsOneWidget);
    expect(find.textContaining('Pip\'s set to watch for Starlink trains'), findsOneWidget);
    expect(find.textContaining('aurora', findRichText: true), findsNothing, reason: 'turned off, so never pitched');
    expect(find.byKey(const Key('offer-light-aurora')), findsNothing);
    expect(find.descendant(of: find.byKey(const Key('trial-offer-sights')), matching: find.textContaining('Starlink')), findsOneWidget);
    // And the rest of LookUp+, once, here; the sky through history isn't sold.
    // What Apple asks for wherever a subscription is sold.
    expect(find.byKey(const Key('terms-link')), findsOneWidget);
    expect(find.byKey(const Key('privacy-link')), findsOneWidget);
    expect(find.textContaining('renews each year until you cancel'), findsOneWidget, reason: 'no store in tests: no price to show');
    for (final k in ['planAhead', 'places', 'transits', 'noCaption']) {
      expect(find.byKey(Key('perk-$k')), findsOneWidget, reason: k);
    }
    for (final k in ['alerts', 'camera', 'timelapse', 'whereToGo', 'history']) {
      expect(find.byKey(Key('perk-$k')), findsNothing, reason: '$k is a switch above, or not sold');
    }
    expect(find.textContaining('history'), findsNothing);
    await t.tap(find.byKey(const Key('trial-offer-not-now')));
    await settle(t);
    final s = container.read(settingsProvider).value!;
    expect((s.onboarded, s.trialOfferShown, s.plusDeclines), (true, true, 1));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('light up your sky: each switch turns it on, Starlink drops in the real tap, all on says keep it', (t) async {
    await toOffer(t);
    expect(find.byKey(const Key('offer-sky')), findsOneWidget);
    expect(find.text('0 of 5 on'), findsOneWidget);
    expect(find.byKey(const Key('offer-tap-preview')), findsNothing);
    Future<void> flip(String k) async {
      await t.ensureVisible(find.byKey(Key('offer-light-$k')));
      await t.tap(find.byKey(Key('offer-light-$k')));
      await settle(t, 2);
    }

    await flip('starlink');
    expect(find.text('1 of 5 on'), findsOneWidget);
    // The tap they'd get, from the real train coming tomorrow.
    expect(find.byKey(const Key('offer-tap-preview')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('offer-tap-preview')), matching: find.text('Starlink train in 10 min')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('offer-tap-preview')), matching: find.text('Example')), findsNothing);
    await settle(t, 16);
    expect(find.byKey(const Key('offer-tap-preview')), findsNothing, reason: 'it goes away by itself');
    // Aurora: none coming, so the tap says it's an example.
    await flip('aurora');
    expect(find.descendant(of: find.byKey(const Key('offer-tap-preview')), matching: find.text('Example')), findsOneWidget);
    for (final k in ['darker', 'timelapse']) {
      await flip(k);
    }
    expect(find.text('Try 7 days free'), findsOneWidget);
    await flip('camera');
    expect(find.text('5 of 5 on'), findsOneWidget);
    expect(find.text('Keep it all on: 7 days free'), findsOneWidget);
    // Off again is one tap; and none of this changes their alert settings.
    await flip('camera');
    expect(find.text('Try 7 days free'), findsOneWidget);
    expect(container.read(settingsProvider).value!.tiangongEnabled, isFalse);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('switches left as they were: the offer names them without saying they asked', (t) async {
    await toOffer(t);
    expect(find.text('Aurora and Starlink trains are LookUp+'), findsOneWidget);
    expect(find.textContaining('Pip\'s set to watch for aurora and Starlink trains'), findsOneWidget);
    expect(find.textContaining('You asked'), findsNothing, reason: 'leaving a switch on isn\'t asking');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('aurora and Starlink both turned off: neither is pitched, the rest of LookUp+ is', (t) async {
    await toOffer(t, off: {'aurora', 'starlink'});
    expect(find.text('Want more from your sky?'), findsOneWidget);
    expect(find.textContaining('Starlink'), findsNothing, reason: 'the coming train is one they said no to');
    expect(find.textContaining('urora'), findsNothing);
    expect(find.byKey(const Key('trial-offer-sights')), findsNothing);
    expect(find.text('0 of 3 on'), findsOneWidget, reason: 'darker skies, timelapses, the Pro camera');
    for (final k in ['alerts', 'planAhead', 'places', 'transits', 'noCaption']) {
      expect(find.byKey(Key('perk-$k')), findsOneWidget, reason: k);
    }
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('replaying the intro from Settings: every page, the offer too, and nothing saved or asked', (t) async {
    // Someone set up long ago, on LookUp+, who has seen the offer.
    final before = _here.copyWith(onboarded: true, isPlus: true, trialOfferShown: true, plusDeclines: 1, auroraEnabled: true);
    _start = before;
    addTearDown(() => _start = _here);
    await pump(t, grantLocation: true, preview: true);
    expect(refresh.prefetched, 0);
    await t.tap(find.text('Replay the intro'));
    await settle(t, 3);
    expect(find.text('Preview · nothing is saved'), findsOneWidget);
    await toSky(t);
    expect(location.asked, 0, reason: 'no location prompt: their place is known');
    expect(home.refreshes, 0, reason: 'no refresh: it shows the sky they already have');
    await catchJupiter(t);
    await t.tap(find.text('Next'));
    await settle(t, 3);
    await catchStation(t);
    await t.tap(find.text('Next'));
    await settle(t, 3);
    t.widget<Slider>(find.byKey(const Key('twilight-slider'))).onChanged!(19);
    await settle(t, 2);
    await t.tap(find.text('Next'));
    await settle(t, 3);
    // A choice on the alerts page goes into the preview's copy, not their settings.
    await t.ensureVisible(find.byKey(const Key('pick-aurora')));
    await settle(t, 1);
    await t.tap(find.byKey(const Key('pick-aurora')));
    await settle(t, 1);
    await t.ensureVisible(find.text('Next'));
    await t.tap(find.text('Next'));
    await settle(t, 3);
    await t.tap(find.text('Tap me 10 minutes before'));
    await settle(t, 4);
    expect(notifications.asked, 0, reason: 'no alerts prompt');
    // The offer shows as it does for someone new, though they have LookUp+.
    expect(find.byKey(const Key('trial-offer')), findsOneWidget);
    await t.tap(find.byKey(const Key('trial-offer-try')));
    await settle(t, 3);
    expect(find.byType(PaywallSheet), findsNothing, reason: 'nothing is sold in a preview');
    expect(find.byKey(const Key('trial-offer')), findsNothing, reason: 'the end just closes it');
    expect(find.text('Replay the intro'), findsOneWidget);
    final after = container.read(settingsProvider).value!;
    expect((after.onboarded, after.isPlus, after.trialOfferShown, after.plusDeclines, after.auroraEnabled), (true, true, true, 1, true),
        reason: 'their settings are exactly as they were');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the preview can be left from any page', (t) async {
    await pump(t, grantLocation: true, preview: true);
    await t.tap(find.text('Replay the intro'));
    await settle(t, 3);
    await t.tap(find.byKey(const Key('onboarding-wake')));
    await settle(t, 3);
    await t.tap(find.byKey(const Key('intro-preview-close')));
    await settle(t, 3);
    expect(find.text('Replay the intro'), findsOneWidget);
    expect(find.text('Preview · nothing is saved'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a denied location offers a town, not a dead end', (t) async {
    _start = const LookUpSettings();
    addTearDown(() => _start = _here);
    await pump(t, grantLocation: false);
    await t.tap(find.byKey(const Key('onboarding-wake')));
    await settle(t, 3);
    await t.tap(find.text('Show me my sky'));
    await t.pump();
    await t.pump();
    expect(find.text('Choose your town'), findsOneWidget);
    expect(find.text('Try location again'), findsOneWidget);
    expect(container.read(settingsProvider).value?.onboarded ?? false, isFalse);
    expect(notifications.asked, 0);
    await t.pumpWidget(const SizedBox());
  });

  for (final (what, start) in [
    ('LookUp+ already', _here.copyWith(isPlus: true)),
    ('already seen once', _here.copyWith(trialOfferShown: true)),
  ]) {
    testWidgets('no trial offer: $what', (t) async {
      _start = start;
      addTearDown(() => _start = _here);
      await pump(t, grantLocation: true, things: const []);
      home.passes = false;
      await toSky(t);
      // Nothing up tonight and no pass coming: straight to a practice pass.
      clock = clock.add(const Duration(milliseconds: 4500));
      await settle(t, 8);
      await t.tap(find.byKey(const Key('first-look-catch')));
      await settle(t, 3);
      await t.tap(find.text('Next'));
      await settle(t, 3);
      await t.tap(find.text('Skip'));
      await settle(t, 3);
      await t.ensureVisible(find.text('Next'));
      await t.tap(find.text('Next'));
      await settle(t, 3);
      await t.tap(find.text('Not now'));
      await settle(t);
      expect(find.byKey(const Key('trial-offer')), findsNothing);
      expect(container.read(settingsProvider).value?.onboarded, isTrue);
      expect(container.read(settingsProvider).value?.plusDeclines, 0);
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets('allowed, but no fix came: a town instead of a wait', (t) async {
    _start = const LookUpSettings();
    addTearDown(() => _start = _here);
    await pump(t, grantLocation: true);
    await toSky(t);
    expect(find.text('Choose your town'), findsOneWidget);
    expect(find.byKey(const Key('first-look')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
