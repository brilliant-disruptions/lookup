import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/services/plus_service.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/ui/theme.dart';
import 'package:lookup/ui/upcoming_screen.dart';

class _Settings extends SettingsNotifier {
  _Settings(this.plus);
  final bool plus;
  @override
  Future<LookUpSettings> build() async =>
      LookUpSettings(latitude: 36.17, longitude: -86.78, placeName: 'Nashville', onboarded: true, isPlus: plus);
}

final _now = DateTime.now().toUtc();

SkyEvent _ev(String id, SkyEventType type, Duration from, {int? clouds, bool past = false}) => SkyEvent(
      id: id,
      type: type,
      start: _now.add(from),
      peak: _now.add(from + const Duration(minutes: 2)),
      end: _now.add(from + const Duration(minutes: 5)),
      peakElevationDeg: 50,
      riseAzimuthDeg: 250,
      peakAzimuthDeg: 180,
      setAzimuthDeg: 90,
      cloudCoverPercent: clouds,
      details: {'label': 'Starlink train', 'count': 22, if (past) 'past': true},
    );

class _Home extends HomeNotifier {
  @override
  Future<HomeData> build() async => HomeData(
        events: [
          _ev('iss:next', SkyEventType.iss, const Duration(hours: 4)),
          _ev('starlink:next', SkyEventType.starlinkTrain, const Duration(days: 1)),
        ],
        recent: [
          _ev('starlink:missed', SkyEventType.starlinkTrain, const Duration(days: -1), clouds: 10, past: true),
          _ev('tiangong:cloudy', SkyEventType.tiangong, const Duration(days: -2), clouds: 95, past: true),
          _ev('aurora:missed', SkyEventType.auroraNow, const Duration(days: -3), clouds: 20, past: true),
        ],
        aurora: null,
        lastRefresh: _now,
        errors: const [],
      );
  @override
  Future<void> refresh({bool force = false, bool quick = false}) async {}
}

class _FakePlus implements PlusService {
  @override
  Stream<String> get errors => const Stream.empty();
  @override
  Future<List<PlusOffer>> offers() async => const [];
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  Future<void> pump(WidgetTester t, {required bool plus}) async {
    t.view.physicalSize = const Size(1179, 6000); // tall enough to lay out the whole week
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith(() => _Settings(plus)),
        homeProvider.overrideWith(_Home.new),
        plusServiceProvider.overrideWithValue(_FakePlus()),
        clockProvider.overrideWith((_) => Stream.value(DateTime.now())),
      ],
      child: MaterialApp(theme: buildLookUpTheme(), home: const UpcomingScreen()),
    ));
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets('on free, the week shows what clear skies you really missed', (t) async {
    await pump(t, plus: false);
    // The train coming tomorrow is Plus-only (the last one: last week's
    // trains sit above it).
    await t.ensureVisible(find.bySemanticsLabel(RegExp(r'^Starlink train, ')).last);
    await t.pump();
    await t.tap(find.bySemanticsLabel(RegExp(r'^Starlink train, ')).last);
    await t.pump();
    expect(find.text('Alert with LookUp+'), findsOneWidget);

    // Last week is a page back, with what was missed at its top. The
    // clouded-out Tiangong pass doesn't count.
    await t.tap(find.byKey(const Key('week-prev')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('You missed 2'), findsOneWidget);
    await t.ensureVisible(find.text('Don\'t miss the next one'));
    await t.pump();
    await t.tap(find.text('Don\'t miss the next one'));
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('Restore purchases'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('on Plus there is nothing to have missed', (t) async {
    await pump(t, plus: true);
    expect(find.textContaining('You missed'), findsNothing);
    await t.ensureVisible(find.bySemanticsLabel(RegExp(r'^Starlink train, ')).last);
    await t.pump();
    await t.tap(find.bySemanticsLabel(RegExp(r'^Starlink train, ')).last);
    await t.pump();
    expect(find.text('Alert with LookUp+'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
