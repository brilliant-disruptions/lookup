import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/data/local_store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  test('feedback is stored, replaced per event and capped at 200', () async {
    final store = LocalStore(SharedPreferencesAsync());
    final t = DateTime.utc(2026, 10, 22);
    await store.addFeedback(SeenFeedback(eventId: 'iss:a', seen: false, at: t));
    await store.addFeedback(SeenFeedback(eventId: 'iss:a', seen: false, at: t, reason: 'clouds'));
    var all = await store.loadFeedback();
    expect(all, hasLength(1));
    expect(all.single.reason, 'clouds');

    for (var i = 0; i < 210; i++) {
      await store.addFeedback(SeenFeedback(eventId: 'e$i', seen: true, at: t));
    }
    all = await store.loadFeedback();
    expect(all, hasLength(200));
    expect(all.last.eventId, 'e209');
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
}
