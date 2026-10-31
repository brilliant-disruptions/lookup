import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/sky_event.dart';
import '../domain/plan/week_view.dart';
import '../domain/scheduling/missed.dart';
import '../state/providers.dart';
import '../state/sky_state.dart';
import 'format.dart';
import 'kit/kit.dart';
import 'look_sheet.dart';
import 'paywall_sheet.dart';
import 'places_screen.dart';
import 'theme.dart';
import 'week_views.dart';

/// The week ahead, two ways: every night at a glance, or two weeks as a
/// calendar, with a glider between them. The week behind is one tap away.
class UpcomingScreen extends ConsumerStatefulWidget {
  const UpcomingScreen({super.key});
  @override
  ConsumerState<UpcomingScreen> createState() => _UpcomingScreenState();
}

class _UpcomingScreenState extends ConsumerState<UpcomingScreen> {
  final _pages = PageController();

  /// The night and the sight picked in either view; shared by both.
  DateTime? _night;
  String? _pick;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

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
        title: const Text('The week'),
        place: (place?.isNotEmpty ?? false) ? place! : 'Near you',
        onPlaceTap: () => openPlaces(context),
      ),
      body: SkyBackdrop(
        stars: false,
        child: home.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (d) {
            final now = DateTime.now();
            final nights = weekNights(d.events, now, weather: weather);
            final days = calendarNights(d.events, now, weather: weather);
            final showing = [for (final n in days) ...n.events];
            final pick = showing.where((e) => e.id == _pick).firstOrNull ??
                nights.expand((n) => n.alerts).firstOrNull ??
                showing.firstOrNull;
            final night = _night ?? (pick == null ? nights.first.date : nightOf(pick.start));
            final missed = isPlus ? const <SkyEvent>[] : missedWithoutPlus(d.recent);
            final nextPlus =
                d.events.where((e) => e.plusOnly && e.type.pushes && e.start.isAfter(now.toUtc())).firstOrNull;
            // Room for the "Last 7 nights" pill above the tab bar.
            final bottom = tabBarClearance(context) + 56;

            void pickNight(DateTime n) => setState(() {
                  _night = n;
                  final there = days.where((x) => x.date == n).firstOrNull;
                  _pick = (there?.alerts.firstOrNull ?? there?.events.firstOrNull)?.id ?? _pick;
                });
            void pickEvent(SkyEvent e) => setState(() {
                  _pick = e.id;
                  _night = nightOf(e.start);
                });

            return Stack(children: [
              Column(children: [
                SizedBox(height: top + 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: WeekGlider(
                    controller: _pages,
                    labels: const ['At a glance', 'Calendar'],
                    icons: const [Icons.view_timeline_rounded, Icons.calendar_month_rounded],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: PageView(controller: _pages, children: [
                    GlancePage(
                      nights: nights,
                      night: night,
                      pick: pick,
                      isPlus: isPlus,
                      onNight: pickNight,
                      onPick: pickEvent,
                      bottomPadding: bottom,
                    ),
                    CalendarPage(days: days, night: night, isPlus: isPlus, onNight: pickNight, bottomPadding: bottom),
                  ]),
                ),
              ]),
              Positioned(
                left: 16,
                right: 16,
                bottom: MediaQuery.paddingOf(context).bottom + 10,
                child: Center(
                  child: _LastWeekPill(
                    recent: d.recent,
                    // Only with something Plus-only really coming: the paywall
                    // never opens without one (spec §7).
                    missed: nextPlus == null ? const [] : missed,
                    onTap: () => _showLastWeek(context, d.recent, missed: nextPlus == null ? const [] : missed,
                        next: nextPlus, lead: settings?.leadMinutes ?? 10, isPlus: isPlus),
                  ),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }

  Future<void> _showLastWeek(BuildContext context, List<SkyEvent> recent,
          {required List<SkyEvent> missed, required SkyEvent? next, required int lead, required bool isPlus}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: LookUpColors.panel,
        builder: (context) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          builder: (context, scroll) => ListView(
            controller: scroll,
            padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.paddingOf(context).bottom + 24),
            children: [
              Text('Last 7 nights', style: display(24, weight: FontWeight.w700)),
              const SizedBox(height: 14),
              if (missed.isNotEmpty) ...[
                _MissedCard(missed: missed, lead: lead, next: next),
                const SizedBox(height: 4),
              ],
              if (recent.isEmpty)
                const _Empty('Nothing passed over in the last week.')
              else
                ..._byNight(recent, past: true, isPlus: isPlus),
            ],
          ),
        ),
      );

  /// Day header, then that day's events on one card.
  List<Widget> _byNight(List<SkyEvent> events, {required bool past, required bool isPlus}) {
    final groups = <String, List<SkyEvent>>{};
    for (final e in events) {
      groups.putIfAbsent(fmtDay(e.start), () => []).add(e);
    }
    final now = DateTime.now().toUtc();
    return [
      for (final g in groups.entries)
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionHeader(g.key, padding: const EdgeInsets.fromLTRB(4, 24, 4, 10)),
          GroupedList(indent: 64, children: [
            for (final e in g.value)
              _EventRow(e,
                  past: past,
                  now: !past && !now.isBefore(e.start) && now.isBefore(e.end),
                  locked: !isPlus && e.plusOnly && e.type.pushes),
          ]),
        ]),
    ];
  }
}

/// "Last 7 nights", and how many clear Plus-only sights went by unseen.
class _LastWeekPill extends StatelessWidget {
  const _LastWeekPill({required this.recent, required this.missed, required this.onTap});
  final List<SkyEvent> recent;
  final List<SkyEvent> missed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hot = missed.isNotEmpty;
    final color = hot ? LookUpColors.orange : LookUpColors.grey;
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: LookUpColors.panel.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: hot ? LookUpColors.orange.withValues(alpha: 0.35) : LookUpColors.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.history_rounded, size: 16, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                hot
                    ? 'Last 7 nights · You missed ${missed.length}'
                    : recent.isEmpty
                        ? 'Last 7 nights'
                        : 'Last 7 nights · ${recent.length}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded, size: 17, color: color),
          ]),
        ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow(this.e, {required this.past, required this.now, this.locked = false});
  final SkyEvent e;
  final bool past;
  final bool now;

  /// Plus-only, for someone on free: no tap unless they upgrade.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final quiet = past || !e.type.pushes;
    return ListRow(
      onTap: () => showLookSheet(context, e),
      leading: EventGlyph.of(e, dim: past),
      title: past ? pastTitle(e) : eventTitle(e),
      titleColor: quiet ? LookUpColors.grey : LookUpColors.white,
      subtitle: past ? pastVerdict(e) : eventSubtitle(e),
      trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
        Text(fmtTime(e.start), style: numeric(size: 14, weight: FontWeight.w600, color: quiet ? LookUpColors.grey : LookUpColors.white)),
        if (now) ...[
          const SizedBox(height: 4),
          const Pill('Now', dot: true, color: LookUpColors.good),
        ] else if (!past && !e.type.pushes) ...[
          const SizedBox(height: 4),
          const Text('No alert', style: TextStyle(fontSize: 11.5, color: LookUpColors.greyDim)),
        ] else if (!past && locked) ...[
          const SizedBox(height: 4),
          const Text('LookUp+', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: LookUpColors.blue)),
        ],
      ]),
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
              Flexible(
                child: Text('${fmtDay(e.start)}, ${fmtTime(e.start)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontSize: 12.5, color: LookUpColors.grey)),
              ),
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

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 0),
        child: Text(text, style: const TextStyle(color: LookUpColors.grey, height: 1.45)),
      );
}
