import 'package:flutter/material.dart';
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
  Future<void> refresh({bool force = false}) async {}
}

PlusOffer _offer(String id, String price, double raw) => PlusOffer(
      id: id,
      title: id,
      price: price,
      details: ProductDetails(
          id: id, title: id, description: '', price: price, rawPrice: raw, currencyCode: 'USD', currencySymbol: r'$'),
    );

class _FakePlus implements PlusService {
  final bought = <String>[];
  @override
  Future<List<PlusOffer>> offers() async => [
        _offer(PlusProducts.yearly, r'$29.99', 29.99),
        _offer(PlusProducts.monthly, r'$5.99', 5.99),
        _offer(PlusProducts.lifetime, r'$59.99', 59.99),
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

    // Yearly is picked, priced per month and against monthly, trial spelled out.
    expect(find.text(r'≈ $2.50 a month'), findsOneWidget);
    expect(find.text('Save 58%'), findsOneWidget);
    expect(find.textContaining(r'$29.99 a year begins'), findsOneWidget);
    expect(find.text('Try 7 days free'), findsOneWidget);

    // Picking monthly changes the one button, and drops the trial timeline.
    await t.tap(find.text('Monthly'));
    await t.pump();
    expect(find.text(r'Continue · $5.99 a month'), findsOneWidget);
    expect(find.textContaining('a year begins'), findsNothing);

    await t.tap(find.text(r'Continue · $5.99 a month'));
    await t.pump();
    expect(plus.bought, [PlusProducts.monthly]);
    await t.pumpWidget(const SizedBox());
  });
}
