import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_store.dart';
import '../domain/log/sky_log.dart';
import '../domain/scheduling/alert_tuning.dart';
import '../domain/models/settings.dart';
import '../domain/models/sky_event.dart';
import '../services/live_activity.dart';
import '../services/location_service.dart';
import '../services/widget_service.dart';
import '../services/notification_service.dart';
import '../services/plus_service.dart';
import '../services/refresh_service.dart';

final storeProvider = Provider<LocalStore>((_) => LocalStore());
final notificationServiceProvider =
    Provider<NotificationService>((_) => NotificationService());
final locationServiceProvider =
    Provider<LocationService>((_) => const LocationService());
final widgetServiceProvider = Provider<WidgetService>((_) => const WidgetService());
final liveActivityProvider = Provider<LiveActivityService>((_) => const LiveActivityService());

final refreshServiceProvider = Provider<RefreshService>((ref) => RefreshService(
      store: ref.watch(storeProvider),
      notifications: ref.watch(notificationServiceProvider),
      location: ref.watch(locationServiceProvider),
      onRefreshed: (settings, events) => ref.read(widgetServiceProvider).update(events),
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
  final svc = PlusService(
    onEntitlementChanged: (isPlus) async {
      await ref.read(settingsProvider.notifier).edit((s) => s.copyWith(isPlus: isPlus));
      await ref.read(homeProvider.notifier).refresh();
    },
  );
  ref.onDispose(svc.dispose);
  return svc;
});

/// The user's sky log (badges, counts) from stored "did you see it?" answers.
final skyLogProvider = FutureProvider<SkyLog>((ref) async {
  final f = await ref.watch(storeProvider).loadFeedback();
  return SkyLog.from([for (final x in f) x.toSighting()]);
});

/// What the app has learned from "what got in the way?" answers.
final tuningProvider = FutureProvider<AlertTuning>((ref) async {
  final f = await ref.watch(storeProvider).loadFeedback();
  return AlertTuning.from([for (final x in f) x.toSighting()]);
});

/// Set by onboarding so the shell plays the preview once, right away.
class PlayIntro extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
}

final playIntroProvider = NotifierProvider<PlayIntro, bool>(PlayIntro.new);
