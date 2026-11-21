import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/data/local_store.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/log/restore.dart';
import 'package:lookup/domain/photo/catch_tag.dart';
import 'package:lookup/services/photo_library.dart';
import 'package:lookup/services/photo_store.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/ui/keep_catch.dart';
import 'package:lookup/ui/theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

final _png = Uint8List.fromList(const [
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 2, 0, 0, 0, 1, 8, 2, 0, 0, 0, 123, 64, 232, 221, //
  0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 248, 207, 0, 4, 255, 1, 7, 0, 1, 255, 226, 35, 158, 89, //
  0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
]);

final _at = DateTime.utc(2026, 11, 21, 23, 4);
final _jupiter = SkyEvent(
  id: 'planet-jupiter:x',
  type: SkyEventType.planetHighlight,
  start: _at,
  peak: _at,
  end: _at.add(const Duration(minutes: 1)),
  peakElevationDeg: 40,
  riseAzimuthDeg: 100,
  peakAzimuthDeg: 120,
  setAzimuthDeg: 140,
);

class _Photos extends PhotoLibrary {
  _Photos(this.state, {this.pic});
  PhotosAccess state;
  final PhotosAccess answer = PhotosAccess.limited;
  final String? id = 'ph-1';
  final Uint8List? pic;
  int asked = 0;
  final saved = <({CatchTag? tag, double? lat})>[];

  @override
  bool get asks => true;
  @override
  Future<PhotosAccess> access() async => state;
  @override
  Future<PhotosAccess> ask() async {
    asked++;
    return state = answer;
  }

  @override
  Future<SavedPicture> save(Uint8List png, {required String name, CatchTag? tag, double? lat, double? lon}) async {
    saved.add((tag: tag, lat: lat));
    return state == PhotosAccess.denied ? SavedPicture.none : SavedPicture(toPhotos: true, assetId: id);
  }

  @override
  Future<SavedPicture> saveVideo(String path, {String? title, DateTime? at, double? lat, double? lon}) async => SavedPicture.none;
  @override
  Future<Uint8List?> picture(String assetId, {int px = 1600}) async => pic;
  @override
  Future<void> manageLimited() async {}
  @override
  Future<void> openSettings() async {}
  List<FoundCatch> found = [];
  @override
  Future<List<FoundCatch>> albumCatches({int max = 300}) async => found;
}

class _Settings extends SettingsNotifier {
  @override
  Future<LookUpSettings> build() async => const LookUpSettings(latitude: 36.17, longitude: -86.78, onboarded: true, placeName: 'Nashville');
}

void main() {
  late LocalStore store;
  late Directory dir;
  setUp(() async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    store = LocalStore(SharedPreferencesAsync());
    dir = Directory.systemTemp.createTempSync('lookup-photos');
    PhotoStore.testDir = dir;
  });
  tearDown(() {
    PhotoStore.testDir = null;
    dir.deleteSync(recursive: true);
  });

  /// Starts a catch (on the real clock, as it writes files) and returns it.
  Future<Future<SavedPicture>> catchIt(WidgetTester t, _Photos photos) async {
    late BuildContext ctx;
    late WidgetRef r;
    await t.pumpWidget(ProviderScope(
      overrides: [
        photoLibraryProvider.overrideWithValue(photos),
        storeProvider.overrideWithValue(store),
        settingsProvider.overrideWith(_Settings.new),
      ],
      child: MaterialApp(
        theme: buildLookUpTheme(),
        home: Consumer(builder: (context, ref, _) {
          ctx = context;
          r = ref;
          ref.watch(settingsProvider);
          return const Scaffold();
        }),
      ),
    ));
    await t.pump();
    late Future<SavedPicture> f;
    await t.runAsync(() async {
      f = keepCatch(ctx, r, event: _jupiter, png: _png, title: 'Jupiter', at: _at, place: 'Nashville');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await t.pump(const Duration(milliseconds: 500));
    return f;
  }

  testWidgets('the first time on iPhone, LookUp recommends Limited before iOS asks; then the catch goes to the album', (t) async {
    t.view.physicalSize = const Size(1179, 2556);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final photos = _Photos(PhotosAccess.unasked);
    final done = await catchIt(t, photos);
    expect(find.byKey(const Key('photos-access')), findsOneWidget);
    expect(photos.asked, 0, reason: 'LookUp explains before iOS asks');
    final limited = find.byKey(const Key('photos-access-limited'));
    expect(find.descendant(of: limited, matching: find.text('Limit Access…')), findsOneWidget);
    expect(find.descendant(of: limited, matching: find.text('Recommended')), findsOneWidget);
    expect(find.textContaining('You don\'t need to pick any photos'), findsOneWidget);
    expect(find.text('Recommended'), findsOneWidget, reason: 'only Limited is recommended');
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    await t.tap(find.byKey(const Key('photos-access-continue')));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 200));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    expect(find.byKey(const Key('photos-access')), findsNothing);
    await t.runAsync(() => done.timeout(const Duration(seconds: 5)));
    expect(photos.asked, 1);
    // The picture carries its sighting, what, when and where; and its place is set.
    final s = photos.saved.single;
    expect((s.tag!.eventId, s.tag!.title, s.tag!.place, s.tag!.at), (_jupiter.id, 'Jupiter', 'Nashville', _at));
    expect(s.lat, 36.17);
    // The Log keeps the Photos id and only a small copy.
    final f = (await t.runAsync(store.loadFeedback))!.single;
    expect((f.eventId, f.seen, f.photoAsset), (_jupiter.id, true, 'ph-1'));
    expect(f.photo, isNotNull);
  });

  testWidgets('asked once: never explained again', (t) async {
    final photos = _Photos(PhotosAccess.limited);
    final done = await catchIt(t, photos);
    expect(find.byKey(const Key('photos-access')), findsNothing);
    await t.runAsync(() => done);
    expect(photos.asked, 0);
    expect((await t.runAsync(store.loadFeedback))!.single.photoAsset, 'ph-1');
  });

  testWidgets('no Photos access: the catch still counts, and the Log keeps the whole picture', (t) async {
    final photos = _Photos(PhotosAccess.denied);
    final done = await catchIt(t, photos);
    expect((await t.runAsync(() => done))!.toPhotos, isFalse);
    final f = (await t.runAsync(store.loadFeedback))!.single;
    expect((f.seen, f.photoAsset), (true, null));
    final kept = (await t.runAsync(() => const PhotoStore().fileFor(f.photo)))!;
    expect(kept.readAsBytesSync(), _png, reason: 'the whole picture, as before');
  });

  testWidgets('the Log shows it from Photos; if Photos no longer has it, LookUp\'s copy and a line saying so', (t) async {
    final name = (await t.runAsync(() => const PhotoStore().saveBytes('planet-jupiter:x', _png)))!;
    Future<void> show(_Photos photos) async {
      await t.pumpWidget(const SizedBox());
      await t.runAsync(() async {
        await t.pumpWidget(ProviderScope(
          overrides: [photoLibraryProvider.overrideWithValue(photos)],
          child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: SightingPicture(photo: name, asset: 'ph-1', large: true)))),
        ));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await t.pump();
    }

    await show(_Photos(PhotosAccess.limited, pic: _png));
    expect(find.byType(Image), findsOneWidget);
    expect(find.byKey(const Key('picture-gone')), findsNothing);
    await show(_Photos(PhotosAccess.limited));
    expect(find.byKey(const Key('picture-gone')), findsOneWidget);
    expect(find.textContaining('The catch still counts'), findsOneWidget);
  });

  test('Settings always recommends Limited', () {
    expect(photosAccessLine(PhotosAccess.unasked), contains('Limit Access is enough'));
    expect(photosAccessLine(PhotosAccess.limited), contains('as recommended'));
    expect(photosAccessLine(PhotosAccess.full), contains('Limited is enough'));
    expect(photosAccessLine(PhotosAccess.denied), contains('Choose Limited'));
  });

  testWidgets('on a new phone, catches come back from the LookUp album, once', (t) async {
    final photos = _Photos(PhotosAccess.limited, pic: _png)
      ..found = [
        (assetId: 'ph-9', tag: CatchTag(eventId: 'iss:old', title: 'The space station', at: _at, type: 'iss', place: 'Nashville')),
      ];
    late WidgetRef r;
    await t.pumpWidget(ProviderScope(
      overrides: [photoLibraryProvider.overrideWithValue(photos), storeProvider.overrideWithValue(store)],
      child: MaterialApp(home: Consumer(builder: (context, ref, _) {
        r = ref;
        return const Scaffold();
      })),
    ));
    expect(await t.runAsync(() => restoreCatches(r)), 1);
    final f = (await t.runAsync(store.loadFeedback))!.single;
    expect((f.eventId, f.seen, f.type, f.photoAsset), ('iss:old', true, SkyEventType.iss, 'ph-9'));
    expect(await t.runAsync(() => restoreCatches(r)), 0, reason: 'already there');
  });
}
