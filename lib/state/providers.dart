import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_store.dart';
import '../domain/models/settings.dart';
import '../domain/models/sky_event.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/plus_service.dart';
import '../services/refresh_service.dart';

final storeProvider = Provider<LocalStore>((_) => LocalStore());
final notificationServiceProvider =
    Provider<NotificationService>((_) => NotificationService());
final locationServiceProvider =
    Provider<LocationService>((_) => const LocationService());
final refreshServiceProvider = Provider<RefreshService>((ref) => RefreshService(
      store: ref.watch(storeProvider),
      notifications: ref.watch(notificationServiceProvider),
      location: ref.watch(locationServiceProvider),
    ));

class SettingsNotifier extends AsyncNotifier<LookUpSettings> {
  @override
  Future<LookUpSettings> build() => ref.watch(storeProvider).loadSettings();

  Future<void> edit(LookUpSettings Function(LookUpSettings) f) async {
    final current = state.value ?? await future;
    final next = f(current);
    state = AsyncData(next);
    await ref.read(storeProvider).saveSettings(next);
  }
}

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, LookUpSettings>(SettingsNotifier.new);

class HomeData {
  const HomeData({
    required this.events,
    required this.aurora,
    required this.lastRefresh,
    required this.errors,
    this.recent = const [],
  });
  final List<SkyEvent> events;

  /// Real events from the last 7 nights, newest first.
  final List<SkyEvent> recent;
  final AuroraSnapshot? aurora;
  final DateTime? lastRefresh;
  final List<String> errors;

  SkyEvent? get next => events.where((e) => e.type != SkyEventType.auroraOutlook).firstOrNull;

  /// The app has never managed to load orbit data (offline first launch).
  bool get noData => lastRefresh == null && events.isEmpty && errors.isNotEmpty;
  SkyEvent? get auroraOutlook =>
      events.where((e) => e.type == SkyEventType.auroraOutlook).firstOrNull;
}

class HomeNotifier extends AsyncNotifier<HomeData> {
  @override
  Future<HomeData> build() async {
    final store = ref.watch(storeProvider);
    final now = DateTime.now().toUtc();
    final events = (await store.loadEvents())
        .where((e) => e.end.isAfter(now))
        .toList();
    return HomeData(
      events: events,
      recent: await store.loadRecent(),
      aurora: await store.loadAurora(),
      lastRefresh: await store.loadLastRefresh(),
      errors: const [],
    );
  }

  /// Fetch + recompute + reschedule, then reload.
  Future<void> refresh({bool force = false}) async {
    final report = await ref
        .read(refreshServiceProvider)
        .run(force: force, allowLocationPrompt: true);
    ref.invalidate(settingsProvider); // location may have been updated
    final store = ref.read(storeProvider);
    state = AsyncData(HomeData(
      events: report.events,
      recent: report.recent,
      aurora: await store.loadAurora(),
      lastRefresh: await store.loadLastRefresh(),
      errors: report.errors,
    ));
  }
}

final homeProvider = AsyncNotifierProvider<HomeNotifier, HomeData>(HomeNotifier.new);

/// Ticks once a second for countdowns.
final clockProvider = StreamProvider<DateTime>(
    (_) => Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now()));

/// Event id from a tapped notification; the app opens its Look sheet.
class TappedEventId extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? id) => state = id;
}

final tappedEventIdProvider = NotifierProvider<TappedEventId, String?>(TappedEventId.new);

/// Store billing. Entitlement flows into settings.isPlus and triggers a
/// re-plan so Plus-only alerts get scheduled right away.
final plusServiceProvider = Provider<PlusService>((ref) {
  final svc = PlusService(onEntitlementChanged: (isPlus) async {
    await ref.read(settingsProvider.notifier).edit((s) => s.copyWith(isPlus: isPlus));
    await ref.read(homeProvider.notifier).refresh();
  });
  ref.onDispose(svc.dispose);
  return svc;
});
