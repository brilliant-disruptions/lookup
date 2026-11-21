/// The soft LookUp+ asks, held to one budget (domain/plus/nudges.dart):
/// Home's one card (a storm tonight, "You missed it", or "LookUp+ near
/// you"), and the helpers every soft ask uses to open the paywall and to
/// count a "Not now".
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/settings.dart';
import '../domain/models/sky_event.dart';
import '../domain/plus/free_plan.dart';
import '../domain/scheduling/alert_planner.dart';
import '../domain/plus/missed_it.dart';
import '../domain/plus/nudges.dart';
import '../domain/plus/plus_preview.dart';
import '../domain/plus/storm.dart';
import '../state/providers.dart';
import 'format.dart';
import 'kit/kit.dart';
import 'paywall_sheet.dart';
import 'plus_card.dart';
import 'theme.dart';

/// Whether [a] may show now, by the shared budget.
bool softAskAllowed(WidgetRef ref, SoftAsk a, LookUpSettings s, {DateTime? now}) => NudgeBudget.allows(
      a,
      isPlus: s.isPlus,
      now: now ?? DateTime.now(),
      onboardedAt: s.onboardedAt,
      declines: s.plusDeclines,
      shownThisSession: ref.read(softAskSessionProvider),
    );

/// A soft ask is on screen: it keeps this session's slot.
void claimSoftAsk(WidgetRef ref, SoftAsk a) =>
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(softAskSessionProvider.notifier).claim(a));

/// "Not now" on a soft ask. Two and they stop.
Future<void> declineSoftAsk(WidgetRef ref) =>
    ref.read(settingsProvider.notifier).edit((s) => s.copyWith(plusDeclines: s.plusDeclines + 1));

/// The paywall from a soft ask: closing it without starting LookUp+ counts
/// as a "Not now".
Future<void> openSoftPaywall(BuildContext context, WidgetRef ref, {SkyEvent? reason, PlusFeature? feature, String? headline}) async {
  await showPaywall(context, reason: reason, feature: feature, headline: headline);
  if (!(ref.read(settingsProvider).value?.isPlus ?? false)) await declineSoftAsk(ref);
}

/// Home's one soft ask, below "Coming up", picked once when Home first has
/// its data and kept while the app runs: the most time-critical of a storm
/// tonight, a sight they missed last night, or the Plus-only taps coming.
/// Usually nothing.
class HomeAsk extends ConsumerStatefulWidget {
  const HomeAsk({super.key, required this.home});
  final HomeData home;
  @override
  ConsumerState<HomeAsk> createState() => _HomeAskState();
}

class _HomeAskState extends ConsumerState<HomeAsk> with AutomaticKeepAliveClientMixin {
  ({SoftAsk ask, SkyEvent? event})? _choice;
  bool _decided = false, _gone = false;

  @override
  bool get wantKeepAlive => true;

  void _decide(LookUpSettings s) {
    _decided = true;
    final now = DateTime.now();
    final d = widget.home;
    // Only kinds they still want: a sight they turned off is never pitched.
    bool wanted(SkyEvent e) => AlertPlanner.typeEnabled(e.type, s);
    final storm = s.auroraEnabled ? stormTonight(d.events, now) : null; // built from the outlook, which never pushes
    final missed = missedIt(recent: d.recent.where(wanted).toList(), now: now, toldId: s.missedItId, toldAt: s.missedItAt);
    final nearYou = PlusPreview.show(isPlus: s.isPlus, snoozedUntil: s.plusCardSnoozedUntil, now: now) &&
        PlusPreview.of(d.events, now, wants: s).count > 0;
    final pick = NudgeBudget.pickForHome([
      if (storm != null && softAskAllowed(ref, SoftAsk.storm, s, now: now)) SoftAsk.storm,
      if (missed != null && softAskAllowed(ref, SoftAsk.missedIt, s, now: now)) SoftAsk.missedIt,
      if (nearYou && softAskAllowed(ref, SoftAsk.nearYou, s, now: now)) SoftAsk.nearYou,
    ]);
    if (pick == null) return;
    _choice = (ask: pick, event: switch (pick) { SoftAsk.storm => storm, SoftAsk.missedIt => missed, _ => null });
    claimSoftAsk(ref, pick);
    // Remembered, so each comes back only on its own cadence.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final u = DateTime.now().toUtc();
      ref.read(settingsProvider.notifier).edit((x) => switch (pick) {
            SoftAsk.missedIt => x.copyWith(missedItId: missed!.id, missedItAt: u),
            // "Near you" at most every three days.
            SoftAsk.nearYou => x.copyWith(plusCardSnoozedUntil: u.add(const Duration(days: 3))),
            _ => x,
          });
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = ref.watch(settingsProvider).value;
    if (s == null) return const SizedBox.shrink();
    if (!_decided) _decide(s);
    final c = _choice;
    if (c == null || _gone || s.isPlus) return const SizedBox.shrink();
    void notNow() {
      setState(() => _gone = true);
      declineSoftAsk(ref);
    }

    return Padding(
      key: Key('home-ask-${c.ask.name}'),
      padding: const EdgeInsets.only(top: 18),
      child: switch (c.ask) {
        SoftAsk.storm => _AskCard(
            tint: LookUpColors.good,
            kicker: 'Storm tonight',
            title: 'The aurora could reach you tonight',
            body: 'A geomagnetic storm is under way. LookUp+ taps you the moment it\'s visible from here, so you don\'t have to keep checking.',
            action: 'Get aurora alerts',
            onAction: () => openSoftPaywall(context, ref,
                feature: PlusFeature.alerts, headline: 'Get tapped the moment the aurora\'s visible from here.'),
            onNotNow: notNow,
          ),
        SoftAsk.missedIt => _AskCard(
            tint: eventStyle(c.event!.type, details: c.event!.details).color,
            kicker: 'While you were away',
            title: _missedTitle(c.event!),
            body: '${fmtDay(c.event!.start)}, ${fmtTime(c.event!.start)}, under clear skies. LookUp+ would have tapped you.',
            action: 'Don\'t miss the next one',
            onAction: () => openSoftPaywall(context, ref,
                feature: PlusFeature.alerts, headline: 'Next time, LookUp+ taps you before it goes over.'),
            onNotNow: notNow,
          ),
        _ => const PlusNearYouCard(chosen: true),
      },
    );
  }

  static String _missedTitle(SkyEvent e) => switch (e.type) {
        SkyEventType.starlinkTrain => 'A Starlink train went over you',
        SkyEventType.tiangong => 'Tiangong went over you',
        SkyEventType.auroraNow => 'The aurora was strong enough to see from here',
        SkyEventType.rocketLaunch => 'A launch was visible from here',
        SkyEventType.comet => 'The comet was up over you',
        _ => '${eventTitle(e)} went over you',
      };
}

/// One quiet card: a kicker, a title, a line, the one action, "Not now".
class _AskCard extends StatelessWidget {
  const _AskCard({
    required this.tint,
    required this.kicker,
    required this.title,
    required this.body,
    required this.action,
    required this.onAction,
    required this.onNotNow,
  });
  final Color tint;
  final String kicker, title, body, action;
  final VoidCallback onAction, onNotNow;

  @override
  Widget build(BuildContext context) => GlassCard(
        tint: tint,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Kicker(kicker, color: tint),
          const SizedBox(height: 4),
          Text(title, style: display(20, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(body, style: const TextStyle(fontSize: 14, color: LookUpColors.grey, height: 1.35)),
          const SizedBox(height: 10),
          Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
            TextButton(
              key: const Key('soft-ask-not-now'),
              onPressed: onNotNow,
              style: TextButton.styleFrom(foregroundColor: LookUpColors.grey),
              child: const Text('Not now'),
            ),
            OutlinedButton(key: const Key('soft-ask-action'), onPressed: onAction, child: Text(action)),
          ]),
        ]),
      );
}
