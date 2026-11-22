import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/sky_event.dart';
import '../domain/plan/week_view.dart';
import '../domain/scheduling/missed.dart';
import '../state/providers.dart';
import '../state/sky_state.dart';
import 'format.dart';
import 'kit/kit.dart';
import 'paywall_sheet.dart';
import 'places_screen.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'week_views.dart';

/// The Week tab: every night at a glance, a week to a page: last week, this
/// week, and the weeks ahead.
class UpcomingScreen extends ConsumerStatefulWidget {
  const UpcomingScreen({super.key});

  @override
  ConsumerState<UpcomingScreen> createState() => _UpcomingScreenState();
}

class _UpcomingScreenState extends ConsumerState<UpcomingScreen> {
  /// The night and the sight picked.
  DateTime? _night;
  String? _pick;

  @override
  Widget build(BuildContext context) {
    final home = ref.watch(homeProvider);
    final settings = ref.watch(settingsProvider).value;
    final weather = ref.watch(weatherProvider).value;
    final place = settings?.placeName;
    final isPlus = settings?.isPlus ?? false;
    final top = MediaQuery.paddingOf(context).top + AppHeader.height;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppHeader(
        title: const Text('Week'),
        place: (place?.isNotEmpty ?? false) ? place! : 'Near you',
        onPlaceTap: () => openPlaces(context),
        actions: const [SettingsButton()],
      ),
      body: SkyBackdrop(
        stars: false,
        child: home.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => LoadTrouble(what: 'Your week didn\'t load.', onRetry: () => ref.invalidate(homeProvider)),
          data: (d) {
            final now = DateTime.now();
            final weeks = glanceWeeks(d.events, d.recent, now, weather: weather);
            final nights = [for (final w in weeks) ...w.nights];
            final showing = [for (final n in nights) ...n.events];
            final pick = showing.where((e) => e.id == _pick).firstOrNull ??
                nights.where((n) => !n.past).expand((n) => n.alerts).firstOrNull ??
                nights.where((n) => !n.past).expand((n) => n.events).firstOrNull;
            final night = _night ?? (pick == null ? dayOf(now) : dayOf(pick.start));
            final missed = isPlus ? const <SkyEvent>[] : missedWithoutPlus(d.recent);
            final nextPlus =
                d.events.where((e) => e.plusOnly && e.type.pushes && e.start.isAfter(now.toUtc())).firstOrNull;

            void pickNight(DateTime n) => setState(() {
                  _night = n;
                  final there = nights.where((x) => x.date == n).firstOrNull;
                  _pick = (there?.alerts.firstOrNull ?? there?.events.firstOrNull)?.id ?? _pick;
                });
            void pickEvent(SkyEvent e) => setState(() {
                  _pick = e.id;
                  _night = dayOf(e.start);
                });

            return Column(children: [
              SizedBox(height: top + 6),
              if (d.satellitesMissing)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Text('Satellite passes will appear once we can reach the tracking data.',
                      textAlign: TextAlign.center, style: TextStyle(color: LookUpColors.greyDim, fontSize: 12.5)),
                ),
              Expanded(
                child: GlancePage(
                  weeks: weeks,
                  night: night,
                  pick: pick,
                  isPlus: isPlus,
                  onNight: pickNight,
                  onPick: pickEvent,
                  bottomPadding: MediaQuery.paddingOf(context).bottom + 12,
                  // Only with something Plus-only really coming: the paywall
                  // never opens without one (spec §7).
                  missed: nextPlus == null || missed.isEmpty
                      ? null
                      : _MissedCard(missed: missed, lead: settings?.leadMinutes ?? 10, next: nextPlus),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

/// "You missed it": Plus-only sights that really went over in clear sky
/// last week, for someone on free. Loss is the honest pitch here, because
/// every one of these happened.
class _MissedCard extends StatelessWidget {
  const _MissedCard({required this.missed, required this.lead, this.next});
  final List<SkyEvent> missed;
  final int lead;

  /// The next Plus-only thing coming, for the paywall's headline.
  final SkyEvent? next;

  @override
  Widget build(BuildContext context) {
    final n = missed.length;
    return GlassCard(
      tint: LookUpColors.orange,
      onTap: () => showPaywall(context, reason: next),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Kicker('Last 7 nights', color: LookUpColors.orange),
        const SizedBox(height: 6),
        Text(n == 1 ? 'You missed one' : 'You missed $n', style: display(26, weight: FontWeight.w700)),
        const SizedBox(height: 10),
        for (final e in missed.take(3))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              EventGlyph.of(e, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(pastTitle(e), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              // When is the point of the row: short, and never cut off (the
              // name gives way instead).
              Text(fmtDayShortTime(e.start),
                  maxLines: 1, style: const TextStyle(fontSize: 12.5, color: LookUpColors.grey)),
            ]),
          ),
        const SizedBox(height: 2),
        Text(
          'Each under a mostly clear sky over you. LookUp+ would have tapped you $lead minutes before.',
          style: const TextStyle(color: LookUpColors.grey, height: 1.4),
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: () => showPaywall(context, reason: next),
          child: const Text('Don\'t miss the next one'),
        ),
      ]),
    );
  }
}
