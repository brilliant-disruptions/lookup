import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/data/backend.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/services/analytics.dart';
import 'package:lookup/services/widget_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _FakeBackend extends BackendClient {
  _FakeBackend() : super(const BackendConfig(url: 'https://x.supabase.co', anonKey: 'k'));
  final sent = <List<Map<String, Object?>>>[];
  bool fail = false;
  @override
  Future<void> track(String installId, List<Map<String, Object?>> events) async {
    if (fail) throw Exception('offline');
    sent.add(events);
  }
}

void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());

  test('analytics queues, flushes in batches, survives offline, honours opt-out', () async {
    final backend = _FakeBackend();
    final a = Analytics(backend: backend, prefs: SharedPreferencesAsync());
    final id = await a.installId();
    expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(await a.installId(), id); // stable

    await a.log('app_open');
    await a.log('seen_yes', {'type': 'iss'});
    backend.fail = true;
    await a.flush();
    expect(backend.sent, isEmpty); // kept for later
    backend.fail = false;
    await a.flush();
    expect(backend.sent.single.map((e) => e['name']), ['app_open', 'seen_yes']);
    await a.flush();
    expect(backend.sent, hasLength(1)); // queue drained

    await a.setOptOut(true);
    await a.log('app_open');
    await a.flush();
    expect(backend.sent, hasLength(1));
  });

  test('analytics without a backend is a no-op', () async {
    final a = Analytics(prefs: SharedPreferencesAsync());
    await a.log('app_open');
    await a.flush();
  });

  test('widget payload: next event or a quiet sky', () {
    expect(WidgetService.payloadFor(null)['next_title'], 'A quiet sky');
    final start = DateTime.utc(2026, 10, 26, 0, 42);
    final e = SkyEvent(
      id: 'iss:w',
      type: SkyEventType.iss,
      start: start,
      peak: start.add(const Duration(minutes: 2)),
      end: start.add(const Duration(minutes: 4)),
      peakElevationDeg: 62,
      riseAzimuthDeg: 247,
      peakAzimuthDeg: 180,
      setAzimuthDeg: 95,
    );
    final p = WidgetService.payloadFor(e);
    expect(p['next_title'], 'ISS flyover');
    expect(p['next_direction'], 'Look west-southwest, high in the sky');
    expect(p['next_start_ms'], start.millisecondsSinceEpoch);
  });
}
