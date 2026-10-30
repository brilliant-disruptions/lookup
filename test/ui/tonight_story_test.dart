import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/services/plus_service.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/state/sky_state.dart';
import 'package:lookup/ui/theme.dart';
import 'package:lookup/ui/tonight_story.dart';

class _Settings extends SettingsNotifier {
  @override
  Future<LookUpSettings> build() async => const LookUpSettings(placeName: 'Nashville', onboarded: true);
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

class _Home extends HomeNotifier {
  @override
  Future<HomeData> build() async => HomeData(
        events: [
          _ev('iss:a', SkyEventType.iss, const Duration(hours: 2), const {'landmarks': 'passing right by Vega'}),
          _ev('starlink:a', SkyEventType.starlinkTrain, const Duration(hours: 4), const {'label': 'Starlink train', 'count': 20}),
        ],
        aurora: null,
        lastRefresh: _now,
        errors: const [],
      );
  @override
  Future<void> refresh({bool force = false}) async {}
}

class _FakePlus implements PlusService {
  @override
  Future<List<PlusOffer>> offers() async => const [];
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  Future<void> pumpViewer(WidgetTester t, {bool still = false, VoidCallback? onClose}) => t.pumpWidget(MaterialApp(
        theme: buildLookUpTheme(),
        home: MediaQuery(
          data: MediaQueryData(size: const Size(400, 800), disableAnimations: still),
          child: StoryViewer(
            pageDuration: const Duration(seconds: 1),
            onClose: onClose ?? () {},
            pages: const [Center(child: Text('A')), Center(child: Text('B')), Center(child: Text('C'))],
          ),
        ),
      ));

  testWidgets('plays page by page and stops on the last', (t) async {
    await pumpViewer(t);
    expect(find.text('A'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 1100));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('B'), findsOneWidget);
    expect(find.text('A'), findsNothing);
    await t.pump(const Duration(milliseconds: 1100));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('C'), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
    expect(find.text('C'), findsOneWidget); // stays
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('tap right for next, left for back; swipe down closes', (t) async {
    var closed = 0;
    await pumpViewer(t, onClose: () => closed++);
    await t.tapAt(const Offset(350, 400));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('B'), findsOneWidget);
    await t.tapAt(const Offset(40, 400));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('A'), findsOneWidget);
    await t.fling(find.text('A'), const Offset(0, 300), 1200);
    await t.pump();
    expect(closed, 1);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('with reduced motion nothing advances on its own', (t) async {
    await pumpViewer(t, still: true);
    await t.pump(const Duration(seconds: 3));
    expect(find.text('A'), findsOneWidget);
    await t.tapAt(const Offset(350, 400));
    await t.pump();
    expect(find.text('B'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('tonight, free: each sight, what LookUp+ would do, and the real next one', (t) async {
    t.view.physicalSize = const Size(1179, 2556);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith(_Settings.new),
        homeProvider.overrideWith(_Home.new),
        tonightSkyProvider.overrideWith((_) async => null),
        plusServiceProvider.overrideWithValue(_FakePlus()),
      ],
      child: MaterialApp(
        theme: buildLookUpTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(child: TextButton(onPressed: () => showTonightStory(context), child: const Text('Play'))),
          ),
        ),
      ),
    ));
    await t.pump();
    await t.tap(find.text('Play'));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Tonight over Nashville'), findsOneWidget);

    Future<void> next() async {
      await t.tapAt(const Offset(330, 300));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 200));
      }
    }

    await next();
    expect(find.text('ISS flyover'), findsOneWidget);
    expect(find.text('Look for it passing right by Vega'), findsOneWidget);
    expect(find.textContaining('LookUp+ would tap you'), findsNothing); // the ISS is free

    await next();
    expect(find.text('Starlink train'), findsOneWidget);
    expect(find.textContaining('LookUp+ would tap you at'), findsOneWidget);

    await next();
    expect(find.text('Don\'t miss the next one'), findsOneWidget);
    expect(find.text('See LookUp+'), findsOneWidget);
    expect(find.textContaining('°'), findsNothing);
    expect(t.takeException(), isNull);

    await t.tap(find.byTooltip('Close'));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Play'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
