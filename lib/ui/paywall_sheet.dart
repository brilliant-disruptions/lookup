import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../domain/models/sky_event.dart';
import '../domain/scheduling/alert_planner.dart';
import '../services/plus_service.dart';
import '../state/providers.dart';
import 'format.dart';
import 'kit/kit.dart';
import 'theme.dart';

/// The paywall appears only when a Plus-only event is actually coming for
/// this user (spec §7), or from Settings.
Future<void> showPaywall(BuildContext context, {SkyEvent? reason}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PaywallSheet(reason: reason),
    );

/// Sells the tap, not a feature list: the top of the sheet is the exact
/// notification LookUp+ would send for something really coming over this
/// user, then what else is coming in the next fortnight, then one plan
/// picker and one button, with the trial spelled out.
class PaywallSheet extends ConsumerStatefulWidget {
  const PaywallSheet({super.key, this.reason});
  final SkyEvent? reason;
  @override
  ConsumerState<PaywallSheet> createState() => _PaywallState();
}

class _PaywallState extends ConsumerState<PaywallSheet> {
  List<PlusOffer>? _offers;
  String? _error;
  bool _busy = false;
  String _chosen = PlusProducts.yearly;

  @override
  void initState() {
    super.initState();
    ref.read(plusServiceProvider).offers().then((o) {
      if (!mounted) return;
      setState(() {
        _offers = o;
        if (o.isNotEmpty && !o.any((x) => x.id == _chosen)) _chosen = o.first.id;
      });
    }).catchError((e) {
      if (mounted) setState(() => _error = '$e');
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider).value;
    final isPlus = settings?.isPlus ?? false;
    final lead = settings?.leadMinutes ?? 10;
    final events = ref.watch(homeProvider).value?.events ?? const <SkyEvent>[];
    final ahead = AlertPlanner.plusOnlyAhead(events, DateTime.now());
    final r = widget.reason;
    // The notification to show: the one that brought them here, else the
    // next Plus-only thing really coming over them.
    final preview = r ?? ahead.firstOrNull;
    final rest = ahead.where((e) => e.id != preview?.id).toList();
    final offers = _offers;
    final chosen = offers?.where((o) => o.id == _chosen).firstOrNull;
    final store = Theme.of(context).platform == TargetPlatform.iOS ? 'App Store' : 'Google Play';
    return SafeArea(
      child: Starfield(
        density: 0.00012,
        maxOpacity: 0.45,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Text('LookUp', style: display(32, weight: FontWeight.w800)),
                Text('+', style: display(32, weight: FontWeight.w800, color: LookUpColors.blue)),
              ]),
              const SizedBox(height: 6),
              Text(
                preview == null
                    ? 'Every reason to step outside, not just the space station.'
                    : 'Don\'t find out tomorrow that it went over.',
                style: t.bodyLarge?.copyWith(color: LookUpColors.grey, fontSize: 17),
              ),
              const SizedBox(height: 18),
              _NotificationPreview(event: preview, leadMinutes: lead),
              const SizedBox(height: 8),
              Text(
                preview == null
                    ? 'An example. LookUp+ sends these for auroras, Starlink trains and Tiangong.'
                    : 'The tap you\'d get. ${fmtDay(preview.start)}, ${fmtTime(preview.start.subtract(Duration(minutes: lead)))}.',
                textAlign: TextAlign.center,
                style: t.bodySmall?.copyWith(color: LookUpColors.greyDim),
              ),
              if (rest.isNotEmpty) ...[
                const SizedBox(height: 22),
                const Kicker('Also coming over you'),
                const SizedBox(height: 8),
                GroupedList(indent: 60, children: [for (final e in rest) _AheadRow(e)]),
              ],
              const SizedBox(height: 22),
              const _Perks(),
              const SizedBox(height: 22),
              if (isPlus)
                const Text('You have LookUp+. Thank you.', textAlign: TextAlign.center, style: TextStyle(color: LookUpColors.grey))
              else if (_error != null)
                Text(_error!, style: const TextStyle(color: LookUpColors.warn))
              else if (offers == null)
                const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
              else if (offers.isEmpty)
                Text(
                  'Can\'t reach the $store right now. Check your connection and try again in a moment.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: LookUpColors.grey),
                )
              else ...[
                for (final o in offers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _PlanCard(
                      offer: o,
                      selected: o.id == _chosen,
                      monthly: offers.where((x) => x.id == PlusProducts.monthly).firstOrNull,
                      onTap: _busy ? null : () => setState(() => _chosen = o.id),
                    ),
                  ),
                if (chosen?.id == PlusProducts.yearly) ...[
                  const SizedBox(height: 6),
                  _TrialTimeline(price: chosen!.price, store: store),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy || chosen == null ? null : () => _buy(chosen),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(58)),
                  child: Text(
                    switch (chosen?.id) {
                      PlusProducts.yearly => 'Try 7 days free',
                      PlusProducts.monthly => 'Continue · ${chosen!.price} a month',
                      _ => 'Buy once · ${chosen?.price ?? ''}',
                    },
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
              if (!isPlus)
                TextButton(
                  onPressed: _busy ? null : _restore,
                  child: const Text('Restore purchases'),
                ),
              Text(
                'Subscriptions renew automatically and can be cancelled any time in your $store account. '
                '7-day free trial on yearly, for new subscribers.',
                textAlign: TextAlign.center,
                style: t.bodySmall?.copyWith(color: LookUpColors.greyDim),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _buy(PlusOffer o) async {
    setState(() => _busy = true);
    try {
      await ref.read(plusServiceProvider).buy(o);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      await ref.read(plusServiceProvider).restore();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// A lock-screen notification, drawn as the phone would show it, with the
/// words AlertPlanner really sends. Slides in like one arriving.
class _NotificationPreview extends StatelessWidget {
  const _NotificationPreview({required this.event, required this.leadMinutes});
  final SkyEvent? event;
  final int leadMinutes;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final title = e == null ? 'Aurora now' : AlertPlanner.headsUpTitle(e, leadMinutes);
    final body = e == null ? 'Find a dark spot and look north.' : AlertPlanner.headsUpBody(e);
    final when = e == null ? 'now' : fmtTime(e.start.subtract(Duration(minutes: leadMinutes)));
    return Semantics(
      label: 'Example alert: $title. $body',
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutBack,
        builder: (context, v, child) => Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, -24 * (1 - v)), child: child),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: BoxDecoration(
            color: const Color(0xD9262B38),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: LookUpColors.line),
            boxShadow: [BoxShadow(color: LookUpColors.blue.withValues(alpha: 0.28), blurRadius: 36, spreadRadius: -6)],
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [LookUpColors.night, LookUpColors.black],
                ),
              ),
              alignment: Alignment.center,
              child: e == null
                  ? const EventGlyph(icon: Icons.waves_rounded, color: LookUpColors.good, size: 30)
                  : EventGlyph.of(e, size: 30),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Expanded(
                    child: Text('LOOKUP',
                        style: TextStyle(fontSize: 11.5, letterSpacing: 0.8, fontWeight: FontWeight.w600, color: LookUpColors.grey)),
                  ),
                  Text(when, style: const TextStyle(fontSize: 12, color: LookUpColors.grey)),
                ]),
                const SizedBox(height: 3),
                Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: LookUpColors.white)),
                const SizedBox(height: 2),
                Text(body,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, height: 1.3, color: LookUpColors.white)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Another Plus-only thing coming over, and what free does about it.
class _AheadRow extends StatelessWidget {
  const _AheadRow(this.e);
  final SkyEvent e;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(children: [
          EventGlyph.of(e, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(eventTitle(e), style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('${fmtDay(e.start)} · ${fmtTime(e.start)}', style: const TextStyle(fontSize: 13, color: LookUpColors.grey)),
            ]),
          ),
          const Text('No alert on free', style: TextStyle(fontSize: 12.5, color: LookUpColors.greyDim)),
        ]),
      );
}

class _Perks extends StatelessWidget {
  const _Perks();
  @override
  Widget build(BuildContext context) => Column(children: [
        for (final (type, line) in const [
          (SkyEventType.auroraNow, 'Aurora the moment it starts, with a wake-me option'),
          (SkyEventType.starlinkTrain, 'Starlink trains for two weeks after every launch'),
          (SkyEventType.tiangong, 'Tiangong, China\'s space station, as well as the ISS'),
          (null, 'A one-minute "go outside now" nudge'),
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              type == null
                  ? const EventGlyph(icon: Icons.directions_walk_rounded, color: LookUpColors.blue, size: 26)
                  : EventGlyph.forType(type, size: 26),
              const SizedBox(width: 12),
              Expanded(child: Text(line, style: const TextStyle(fontSize: 14.5, height: 1.3))),
            ]),
          ),
      ]);
}

/// One plan, as a card you pick before the single button below.
class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.offer, required this.selected, required this.onTap, this.monthly});
  final PlusOffer offer;
  final bool selected;
  final VoidCallback? onTap;
  final PlusOffer? monthly;

  @override
  Widget build(BuildContext context) {
    final (label, note) = switch (offer.id) {
      PlusProducts.yearly => ('Yearly', _perMonth(offer)),
      PlusProducts.monthly => ('Monthly', null),
      _ => ('Lifetime', 'Pay once, keep it forever'),
    };
    final save = offer.id == PlusProducts.yearly ? _saving(offer, monthly) : null;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? LookUpColors.blue.withValues(alpha: 0.12) : LookUpColors.panelRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          side: BorderSide(color: selected ? LookUpColors.blue : LookUpColors.line, width: selected ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
            child: Row(children: [
              Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: selected ? LookUpColors.blue : LookUpColors.greyDim, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    if (offer.id == PlusProducts.yearly) const Pill('7 days free', color: LookUpColors.good),
                    if (save != null) Pill(save, color: LookUpColors.blue),
                  ]),
                  if (note != null) ...[
                    const SizedBox(height: 3),
                    Text(note, style: const TextStyle(fontSize: 13, color: LookUpColors.grey)),
                  ],
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(offer.price, style: numeric(size: 16, weight: FontWeight.w700)),
                Text(offer.cadence, style: const TextStyle(fontSize: 12, color: LookUpColors.grey)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  /// "≈ $2.50 a month", from the store's own price and currency.
  static String? _perMonth(PlusOffer yearly) {
    final d = yearly.details;
    if (d.rawPrice <= 0) return null;
    final f = NumberFormat.currency(name: d.currencyCode, symbol: d.currencySymbol);
    return '≈ ${f.format(d.rawPrice / 12)} a month';
  }

  /// "Save 58%" against paying monthly for a year, when it's worth saying.
  static String? _saving(PlusOffer yearly, PlusOffer? monthly) {
    if (monthly == null || monthly.details.currencyCode != yearly.details.currencyCode) return null;
    final full = monthly.details.rawPrice * 12;
    if (full <= 0) return null;
    final pct = ((1 - yearly.details.rawPrice / full) * 100).floor();
    return pct >= 10 ? 'Save $pct%' : null;
  }
}

/// What happens when, so starting a trial isn't a leap of faith.
class _TrialTimeline extends StatelessWidget {
  const _TrialTimeline({required this.price, required this.store});
  final String price;
  final String store;

  @override
  Widget build(BuildContext context) {
    final steps = [
      (Icons.notifications_active_rounded, 'Today', 'Every alert is on, starting tonight.'),
      (Icons.event_rounded, 'Day 7', 'Your trial ends and $price a year begins.'),
      (Icons.cancel_outlined, 'Before then', 'Cancel in your $store account and you won\'t be charged.'),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: LookUpColors.glass, borderRadius: BorderRadius.circular(Radii.md)),
      child: Column(children: [
        for (final (i, (icon, when, what)) in steps.indexed)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 18, color: i == 0 ? LookUpColors.good : LookUpColors.grey),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '$when  ', style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: what, style: const TextStyle(color: LookUpColors.grey)),
                ]), style: const TextStyle(fontSize: 13.5, height: 1.35)),
              ),
            ]),
          ),
      ]),
    );
  }
}
