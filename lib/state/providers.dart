import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_store.dart';
import '../domain/log/sky_log.dart';
import '../domain/scheduling/alert_tuning.dart';
import '../domain/models/settings.dart';
import '../domain/models/sky_event.dart';
import '../domain/plus/nudges.dart' show SoftAsk;
import '../domain/plus/trial_reminder.dart';
import '../domain/plus/plus_grant.dart';
import '../domain/units.dart';
import '../services/ambient_light.dart';
import '../services/lock_screen_catches.dart';
import '../services/live_activity.dart';
import '../services/location_service.dart';
import '../services/widget_service.dart';
import '../services/notification_service.dart';
import '../services/photo_library.dart';
import '../services/plus_service.dart';
import '../services/refresh_service.dart';
import '../services/shortcut_summary.dart';

final storeProvider = Provider<LocalStore>((_) => LocalStore());

/// The phone's own Photos, for caught pictures; tests swap in a fake.
final photoLibraryProvider = Provider<PhotoLibrary>((_) => const GalPhotoLibrary());
final notificationServiceProvider =
    Provider<NotificationService>((_) => NotificationService());
final locationServiceProvider =
    Provider<LocationService>((_) => const LocationService());
final widgetServiceProvider = Provider<WidgetService>((_) => const WidgetService());
final liveActivityProvider = Provider<LiveActivityService>((_) => const LiveActivityService());
final ambientLightProvider = Provider<AmbientLightService>((_) => const AmbientLightService());

/// Auto's red (0–1) from the light around the phone; nothing without a
/// sensor. Auto-dispose so the sensor is only on while night vision is.
final ambientRedProvider =
    StreamProvider.autoDispose<double>((ref) => ref.watch(ambientLightProvider).redStrength());

final refreshServiceProvider = Provider<RefreshService>((ref) => RefreshService(
      store: ref.watch(storeProvider),
      notifications: ref.watch(notificationServiceProvider),
      location: ref.watch(locationServiceProvider),
      onRefreshed: (settings, events) async {
        await ref.read(widgetServiceProvider).update(events);
        await saveShortcutSummary(events);
        // "Saw it" pressed on the Lock Screen while the app was closed.
        final caught = await importLockScreenCatchesFromAppGroup(
            ref.read(storeProvider), ref.read(notificationServiceProvider));
        if (caught > 0) ref.invalidate(skyLogProvider);
      },
    ));

class SettingsNotifier extends AsyncNotifier<LookUpSettings> {
  @override
  Future<LookUpSettings> build() async {
    final store = ref.watch(storeProvider);
    final s = await store.loadSettings();
    if (s.miles != null) return s;
    // First run: miles or kilometres from the phone's region, saved so the
    // background refresh writes alerts in the same units.
    final filled = s.copyWith(miles: countryUsesMiles(PlatformDispatcher.instance.locale.countryCode));
    await store.saveSettings(filled);
    return filled;
  }

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
    this.approximate = false,
    this.satellitesMissing = false,
  });
  final List<SkyEvent> events;

  /// No orbit data for the ISS saved on this phone yet (Celestrak not
  /// reached), so satellite passes are missing until it is. The feed's own
  /// backoff retries it; nothing here forces a fetch.
  final bool satellitesMissing;

  /// The ISS times come from the copy shipped with the app (see
  /// [RefreshReport.approximate]).
  final bool approximate;

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
      satellitesMissing: await store.loadElements('iss') == null,
    );
  }

  /// How long a pull-to-refresh holds the spinner. A full refresh can run for
  /// minutes on a slow or throttled connection (every source retries with
  /// 30–60 s timeouts); past this the spinner stops and the refresh carries
  /// on, updating the screen when it lands.
  static const pullLimit = Duration(seconds: 8);

  /// Pull-to-refresh: like [refresh], but done waiting after [pullLimit].
  /// Not forced: a pull re-plans from what's fresh and only fetches what's
  /// stale, so pulling can't break the feeds' data etiquette (Celestrak once
  /// a day, Open-Meteo 6 h, SWPC 30 min). Settings has "Refresh everything".
  Future<void> pull() => refresh().timeout(pullLimit, onTimeout: () {});

  /// The refresh in progress. Refreshes queue behind it: two at once would
  /// race to save events and planned alerts.
  Future<void> _running = Future.value();
  int _queued = 0;

  /// Whether a refresh is running or queued.
  bool get refreshing => _queued > 0;

  /// Fetch + recompute + reschedule, then reload. [quick] is onboarding's
  /// first look (see [RefreshService.run]).
  Future<void> refresh({bool force = false, bool quick = false}) {
    _queued++;
    final next = _running
        .catchError((_) {})
        .then((_) => _refresh(force: force, quick: quick))
        .whenComplete(() => _queued--);
    _running = next;
    return next;
  }

  Future<void> _refresh({required bool force, required bool quick}) async {
    final report = await ref
        .read(refreshServiceProvider)
        .run(force: force, allowLocationPrompt: true, quick: quick);
    ref.invalidate(settingsProvider); // location may have been updated
    final store = ref.read(storeProvider);
    state = AsyncData(HomeData(
      events: report.events,
      recent: report.recent,
      aurora: await store.loadAurora(),
      lastRefresh: await store.loadLastRefresh(),
      errors: report.errors,
      approximate: report.approximate,
      satellitesMissing: !report.approximate && await store.loadElements('iss') == null,
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

/// The soft LookUp+ ask this app session has shown, if any: the budget in
/// domain/plus/nudges.dart allows one per session, and this is that one.
class SoftAskSession extends Notifier<SoftAsk?> {
  @override
  SoftAsk? build() => null;

  /// Takes the slot, unless another ask already has it.
  void claim(SoftAsk a) => state ??= a;
}

final softAskSessionProvider = NotifierProvider<SoftAskSession, SoftAsk?>(SoftAskSession.new);

/// Store billing. What the store says flows into settings (isPlus and its
/// end date, domain/plus/plus_grant.dart), and a change either way triggers
/// a re-plan so Plus-only alerts are scheduled, or dropped, right away.
final plusServiceProvider = Provider<PlusService>((ref) {
  final svc = PlusService(
    onNews: (news) async {
      final now = DateTime.now().toUtc();
      final before = await ref.read(settingsProvider.future);
      final after = PlusGrant.apply(before, news, now);
      if (identical(after, before)) return;
      // A trial starting: the reminder the paywall promises, 2 days before it ends.
      final remind = trialReminderAt(before, news, now);
      if (remind != null && news is PlusOwned) {
        try {
          await ref.read(notificationServiceProvider).scheduleTrialReminder(remind,
              ends: news.until!, iOS: defaultTargetPlatform == TargetPlatform.iOS);
        } catch (_) {
          // A reminder that can't be set must never cost the purchase.
        }
      }
      await ref.read(settingsProvider.notifier).edit((s) => PlusGrant.apply(s, news, now));
      if (after.isPlus != before.isPlus) await ref.read(homeProvider.notifier).refresh();
    },
  );
  // Back in front after time away: a renewal, a lapse or a refund may have
  // happened meanwhile (silent, like the check at launch).
  final resumed = AppLifecycleListener(onResume: svc.recheck);
  ref.onDispose(resumed.dispose);
  ref.onDispose(svc.dispose);
  return svc;
});

/// The user's sky log (badges, counts) from stored catches, with the
/// "Looked up" badge from setting up ([LookUpSettings.onboardedAt]).
final skyLogProvider = FutureProvider<SkyLog>((ref) async {
  final f = await ref.watch(storeProvider).loadFeedback();
  final onboardedAt = await ref.watch(settingsProvider.selectAsync((s) => s.onboardedAt));
  return SkyLog.from([for (final x in f) x.toSighting()], onboardedAt: onboardedAt);
});

/// What the app has learned from "what got in the way?" answers.
final tuningProvider = FutureProvider<AlertTuning>((ref) async {
  final f = await ref.watch(storeProvider).loadFeedback();
  return AlertTuning.from([for (final x in f) x.toSighting()]);
});

/// Which bottom tab is showing ([HomeTab.home] … [HomeTab.log]), so screens
/// can send you to another one ("See every night").
class HomeTab extends Notifier<int> {
  static const home = 0, week = 1, explore = 2, log = 3;

  @override
  int build() => home;
  void set(int i) => state = i;
}

final homeTabProvider = NotifierProvider<HomeTab, int>(HomeTab.new);

/// Set by onboarding so the shell plays the preview once, right away.
class PlayIntro extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
}

final playIntroProvider = NotifierProvider<PlayIntro, bool>(PlayIntro.new);

/// Whether the app can offer "Add to home screen" for the widget.
final widgetPinnableProvider = FutureProvider<bool>((_) => WidgetService.canPin());
