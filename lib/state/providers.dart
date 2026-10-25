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
import '../services/shortcut_summary.dart';

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
      onRefreshed: (settings, events) async {
        await ref.read(widgetServiceProvider).update(events);
        await saveShortcutSummary(events);
      },
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

  /// The next thing worth stepping out for (what alerts are about).
  SkyEvent? get next => events.where((e) => e.type.pushes).firstOrNull;

  /// Sub-second Sun/Moon crossings in the coming week.
  List<SkyEvent> get transits => [for (final e in events) if (e.type == SkyEventType.issTransit) e];

  /// The app has never managed to load orbit data (offline first launch).
  bool get noData => lastRefresh == null && events.isEmpty && errors.isNotEmpty && !needsLocation;

  /// No location at all: permission refused and no place pinned.
  bool get needsLocation => events.isEmpty && errors.contains('no location');
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

/// Whether alerts can reach the user (null: the platform can't say).
/// Re-checked when the app comes back to the foreground.
final alertsEnabledProvider = FutureProvider<bool?>((ref) => ref.watch(notificationServiceProvider).alertsEnabled());

/// Ticks once a second for countdowns.
final clockProvider = StreamProvider<DateTime>(
    (_) => Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now()));

/// A tapped alert (or one of its buttons) for the shell to act on.
class AlertTap {
  const AlertTap(this.eventId, {this.action});
  final String eventId;

  /// Null for a plain tap; otherwise an [AlertAction] id.
  final String? action;
}

class AlertTaps extends Notifier<AlertTap?> {
  @override
  AlertTap? build() => null;
  void set(AlertTap? t) => state = t;
}

final alertTapProvider = NotifierProvider<AlertTaps, AlertTap?>(AlertTaps.new);

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
