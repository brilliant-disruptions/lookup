import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/data/local_store.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  test('feedback is stored and replaced per event; only "missed it" answers are capped', () async {
    final store = LocalStore(SharedPreferencesAsync());
    final t = DateTime.utc(2026, 10, 22);
    await store.addFeedback(SeenFeedback(eventId: 'iss:a', seen: false, at: t));
    await store.addFeedback(SeenFeedback(eventId: 'iss:a', seen: false, at: t, reason: 'clouds'));
    var all = await store.loadFeedback();
    expect(all, hasLength(1));
    expect(all.single.reason, 'clouds');

    // A catch from long ago, then hundreds of answers.
    await store.addFeedback(SeenFeedback(eventId: 'solar:20260812', seen: true, at: t, type: SkyEventType.solarEclipse));
    for (var i = 0; i < 260; i++) {
      await store.addFeedback(SeenFeedback(eventId: 'e$i', seen: i.isOdd, at: t.add(Duration(days: i + 1))));
    }
    all = await store.loadFeedback();
    expect(all.where((f) => !f.seen), hasLength(131), reason: 'under the 200 kept for tuning');
    expect(all.where((f) => f.seen), hasLength(131), reason: 'every catch, the eclipse included');
    expect(all.any((f) => f.eventId == 'solar:20260812'), isTrue, reason: 'a catch is never pushed out');
    expect(all.last.eventId, 'e259');
  });

  test('the oldest "missed it" answers go first; catches stay', () {
    final t = DateTime.utc(2026, 1, 1);
    final all = [
      for (var i = 0; i < FeedbackStore.maxMissed + 50; i++) SeenFeedback(eventId: 'm$i', seen: false, at: t.add(Duration(hours: i))),
      SeenFeedback(eventId: 'catch', seen: true, at: t),
    ];
    final kept = FeedbackStore.trimLog(all);
    expect(kept.where((f) => !f.seen), hasLength(FeedbackStore.maxMissed));
    expect(kept.first.eventId, 'm50');
    expect(kept.last.eventId, 'catch');
  });

  test('catching something again keeps the day it was first caught', () async {
    final store = LocalStore(SharedPreferencesAsync());
    final first = DateTime.utc(2026, 10, 22, 2);
    await store.addFeedback(SeenFeedback(eventId: 'obj:planet:jupiter', seen: true, at: first));
    await store.addFeedback(SeenFeedback(eventId: 'obj:planet:jupiter', seen: true, at: first.add(const Duration(days: 30))));
    expect((await store.loadFeedback()).single.at, first);
    // A miss, then a catch: the catch's own day.
    await store.addFeedback(SeenFeedback(eventId: 'iss:b', seen: false, at: first));
    await store.addFeedback(SeenFeedback(eventId: 'iss:b', seen: true, at: first.add(const Duration(days: 1))));
    expect((await store.loadFeedback()).last.at, first.add(const Duration(days: 1)));
  });

  test('settings round-trip through the store', () async {
    final store = LocalStore(SharedPreferencesAsync());
    final s = await store.loadSettings();
    expect(s.onboarded, isFalse);
    await store.saveSettings(s.copyWith(onboarded: true, isPlus: true, leadMinutes: 5));
    final rt = await store.loadSettings();
    expect(rt.onboarded, isTrue);
    expect(rt.isPlus, isTrue);
    expect(rt.leadMinutes, 5);
  });

  test('a photo attaches to a sighting and survives answering again', () async {
    final store = LocalStore(SharedPreferencesAsync());
    final t = DateTime.utc(2026, 10, 22);
    await store.addFeedback(SeenFeedback(eventId: 'iss:a', seen: true, at: t));
    await store.setPhoto('iss:a', 'iss_a-1.jpg');
    expect((await store.loadFeedback()).single.toSighting().photo, 'iss_a-1.jpg');
    await store.addFeedback(SeenFeedback(eventId: 'iss:a', seen: true, at: t.add(const Duration(minutes: 1))));
    expect((await store.loadFeedback()).single.photo, 'iss_a-1.jpg');
    await store.setPhoto('iss:missing', 'x.jpg'); // no sighting: ignored
    expect(await store.loadFeedback(), hasLength(1));
  });
}
