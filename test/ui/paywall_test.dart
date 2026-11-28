import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/services/plus_service.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/ui/paywall_sheet.dart';
import 'package:lookup/ui/theme.dart';

class _Settings extends SettingsNotifier {
  @override
  Future<LookUpSettings> build() async => const LookUpSettings(latitude: 36.17, longitude: -86.78, onboarded: true);
}

class _PlusSettings extends SettingsNotifier {
  @override
  Future<LookUpSettings> build() async => const LookUpSettings(latitude: 36.17, longitude: -86.78, onboarded: true, isPlus: true);
}

/// Free, until the store says they've bought it.
class _FlipSettings extends SettingsNotifier {
  @override
  Future<LookUpSettings> build() async => const LookUpSettings(latitude: 36.17, longitude: -86.78, onboarded: true);
  void becomePlus() => state = AsyncData(state.requireValue.copyWith(isPlus: true));
}

final _now = DateTime.now().toUtc();

SkyEvent _ev(String id, SkyEventType type, Duration inFuture, Map<String, Object?> details) => SkyEvent(
      id: id,
      type: type,
      start: _now.add(inFuture),
      peak: _now.add(inFuture + const Duration(minutes: 2)),
      end: _now.add(inFuture + const Duration(minutes: 5)),
      peakElevationDeg: 55,
      riseAzimuthDeg: 300,
      peakAzimuthDeg: 20,
      setAzimuthDeg: 110,
      details: details,
    );

final _events = [
  _ev('iss:a', SkyEventType.iss, const Duration(hours: 3), const {}),
  _ev('starlink:a', SkyEventType.starlinkTrain, const Duration(days: 1), const {'label': 'Starlink train', 'count': 24}),
  _ev('tiangong:a', SkyEventType.tiangong, const Duration(days: 3), const {'brightness': 'as bright as the brightest stars'}),
];

class _Home extends HomeNotifier {
  @override
  Future<HomeData> build() async => HomeData(events: _events, aurora: null, lastRefresh: _now, errors: const []);
  @override
  Future<void> refresh({bool force = false, bool quick = false}) async {}
}

PlusOffer _offer(String id, String price, double raw) => PlusOffer(
      id: id,
      title: id,
      price: price,
      details: ProductDetails(
          id: id, title: id, description: '', price: price, rawPrice: raw, currencyCode: 'USD', currencySymbol: r'$'),
    );

class _FakePlus implements PlusService {
  final failed = StreamController<String>.broadcast();
  int restores = 0;
  bool reachable = true;
  @override
  Stream<String> get errors => failed.stream;
  @override
  Future<void> restore() async {
    restores++;
    if (!reachable) throw 'offline';
  }
  final bought = <String>[];
  @override
  Future<List<PlusOffer>> offers() async => [
        _offer(PlusProducts.yearly, r'$29.99', 29.99),
        _offer(PlusProducts.monthly, r'$5.99', 5.99),
      ];
  @override
  Future<void> buy(PlusOffer offer) async => bought.add(offer.id);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  testWidgets('shows the real alert, what else is coming, and one plan picker', (t) async {
    t.view.physicalSize = const Size(1179, 6000);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final plus = _FakePlus();
    await t.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith(_Settings.new),
        homeProvider.overrideWith(_Home.new),
        plusServiceProvider.overrideWithValue(plus),
      ],
      child: MaterialApp(theme: buildLookUpTheme(), home: const Scaffold(body: PaywallSheet())),
    ));
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }

    // The notification LookUp+ would really send for the next Plus-only pass
    // (the free ISS pass is not it), in AlertPlanner's own words.
    expect(find.text('Starlink train in 10 min'), findsOneWidget);
    expect(find.textContaining('A line of ~24 lights'), findsOneWidget);
    // The rest of what's coming, and what free does about it.
    expect(find.text('Tiangong flyover'), findsOneWidget);
    expect(find.text('No alert on free'), findsOneWidget);

    // Everything LookUp+ adds, from the one list the onboarding offer uses too.
    for (final line in ['The Pro camera', 'Self-starting timelapses', 'Where to go tonight']) {
      expect(find.textContaining(line), findsOneWidget, reason: line);
    }
    expect(find.textContaining('3000 BC'), findsNothing, reason: 'the sky through history isn\'t what LookUp+ is sold on');
    expect(find.byKey(const Key('terms-link')), findsOneWidget);
    expect(find.byKey(const Key('privacy-link')), findsOneWidget);

    // Yearly is picked, priced per month and against monthly, trial spelled out.
    expect(find.text(r'≈ $2.50 a month'), findsOneWidget);
    expect(find.text('Save 58%'), findsOneWidget);
    expect(find.textContaining(r'Then $29.99 a year'), findsOneWidget);
    expect(find.text('Try 7 days free'), findsOneWidget);

    // Picking monthly changes the one button, and drops the trial timeline.
    await t.tap(find.text('Monthly'));
    await t.pump();
    expect(find.text(r'Continue · $5.99 a month'), findsOneWidget);
    expect(find.textContaining('Then'), findsNothing);

    await t.tap(find.text(r'Continue · $5.99 a month'));
    await t.pump();
    expect(plus.bought, [PlusProducts.monthly]);
    await t.pumpWidget(const SizedBox());
  });

  Future<_FakePlus> open(WidgetTester t, {bool isPlus = false}) async {
    t.view.physicalSize = const Size(1179, 6000);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final plus = _FakePlus();
    await t.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith(isPlus ? _PlusSettings.new : _Settings.new),
        homeProvider.overrideWith(_Home.new),
        plusServiceProvider.overrideWithValue(plus),
      ],
      child: MaterialApp(theme: buildLookUpTheme(), home: const Scaffold(body: PaywallSheet())),
    ));
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    return plus;
  }

  // A declined card or a cancelled sheet comes from the store later, not
  // from the button: it used to show nothing at all.
  testWidgets('a purchase that doesn\'t go through says so, in words, and the plans stay', (t) async {
    final plus = await open(t);
    expect(find.byKey(const Key('paywall-note')), findsNothing);
    plus.failed.add('SKErrorDomain 2');
    await t.pump();
    await t.pump();
    final note = t.widget<Text>(find.byKey(const Key('paywall-note'))).data!;
    expect(note, contains('haven\'t been charged'));
    expect(note, isNot(contains('SKError')), reason: 'never the raw error');
    expect(find.byKey(const Key('paywall-buy')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Restore purchases says what it found', (t) async {
    final plus = await open(t);
    // However long the sheet is (it lists what's coming, which varies), scroll to the button first.
    Future<void> restore() async {
      await t.ensureVisible(find.byKey(const Key('restore-purchases')));
      await t.pump();
      await t.tap(find.byKey(const Key('restore-purchases')));
    }

    await restore();
    await t.pump();
    await t.pump();
    expect(plus.restores, 1);
    expect(t.widget<Text>(find.byKey(const Key('paywall-note'))).data, contains('No LookUp+ found'));
    plus.reachable = false;
    await restore();
    await t.pump();
    await t.pump();
    expect(t.widget<Text>(find.byKey(const Key('paywall-note'))).data, contains('Couldn\'t reach the store'));
    await t.pumpWidget(const SizedBox());
  });

  // Subscribing used to leave the sheet up, saying "Thank you", over the
  // screen they came from: it should take them back there.
  testWidgets('becoming a subscriber closes the sheet and goes back', (t) async {
    t.view.physicalSize = const Size(1179, 6000);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final settings = _FlipSettings();
    await t.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith(() => settings),
        homeProvider.overrideWith(_Home.new),
        plusServiceProvider.overrideWithValue(_FakePlus()),
      ],
      child: MaterialApp(
        theme: buildLookUpTheme(),
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(onPressed: () => showPaywall(c), child: const Text('where they were')),
          ),
        ),
      ),
    ));
    await t.pump();
    await t.tap(find.text('where they were'));
    await t.pumpAndSettle();
    expect(find.byType(PaywallSheet), findsOneWidget);

    settings.becomePlus();
    await t.pumpAndSettle();
    expect(find.byType(PaywallSheet), findsNothing);
    expect(find.text('where they were'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a subscriber is shown where to manage or cancel', (t) async {
    await open(t, isPlus: true);
    expect(find.byKey(const Key('manage-subscription')), findsOneWidget);
    expect(find.byKey(const Key('restore-purchases')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('opened from a locked alert, it says that alert is LookUp+', (t) async {
    t.view.physicalSize = const Size(1179, 6000);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith(_Settings.new),
        homeProvider.overrideWith(_Home.new),
        plusServiceProvider.overrideWithValue(_FakePlus()),
      ],
      child: MaterialApp(theme: buildLookUpTheme(), home: Scaffold(body: PaywallSheet(reason: _events[2]))),
    ));
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Tiangong alerts are LookUp+.'), findsOneWidget);
    expect(find.textContaining('Free won\'t alert you to this one'), findsOneWidget);
    expect(find.text('Never miss the next event.'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
