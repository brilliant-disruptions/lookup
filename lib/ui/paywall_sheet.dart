import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../domain/models/sky_event.dart';
import '../domain/plus/free_plan.dart';
import '../domain/scheduling/alert_planner.dart';
import '../services/plus_service.dart';
import '../state/providers.dart';
import 'format.dart';
import 'help.dart';
import 'kit/kit.dart';
import 'plus_perks.dart';
import 'theme.dart';

/// The paywall appears only when a Plus-only event is actually coming for
/// this user (spec §7), or from Settings.
Future<void> showPaywall(BuildContext context, {SkyEvent? reason, PlusFeature? feature, String? headline}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PaywallSheet(reason: reason, feature: feature, headline: headline),
    );

/// Whether this person has LookUp+, read without listening (for taps).
bool hasPlus(BuildContext context) =>
    ProviderScope.containerOf(context, listen: false).read(settingsProvider).value?.isPlus ?? false;

/// What's locked on free, as list rows show it: Plus-only alerts and the
/// photo-planning transits.
bool lockedOnFree(SkyEvent e, {required bool isPlus}) =>
    !isPlus && ((e.plusOnly && e.type.pushes) || e.type == SkyEventType.issTransit);

/// On something whose alert needs LookUp+: you can see it, but you won't be
/// told when it's coming.
class PlusAlertTag extends StatelessWidget {
  const PlusAlertTag({super.key, this.size = 11.5});
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Alert with LookUp+',
        excludeSemantics: true,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lock_rounded, size: size + 1, color: LookUpColors.blue),
          const SizedBox(width: 4),
          Text('Alert with LookUp+',
              style: TextStyle(fontSize: size, fontWeight: FontWeight.w600, color: LookUpColors.blue)),
        ]),
      );
}

/// "Starlink trains are LookUp+.": the one thing that brought them here.
String? _lockedHeadline(SkyEvent e) => switch (e.type) {
      SkyEventType.tiangong => 'Tiangong alerts are LookUp+.',
      SkyEventType.starlinkTrain => 'Starlink train alerts are LookUp+.',
      SkyEventType.auroraNow => 'Live aurora alerts are LookUp+.',
      SkyEventType.rocketLaunch => 'Launch alerts are LookUp+.',
      SkyEventType.occultation => 'Moon cover alerts are LookUp+.',
      SkyEventType.comet || SkyEventType.nova => 'Rare sky alerts are LookUp+.',
      _ => null,
    };

/// Sells the tap, not a feature list: the top of the sheet is the exact
/// notification LookUp+ would send for something really coming over this
/// user, then what else is coming in the next fortnight, then one plan
/// picker and one button, with the trial spelled out.
class PaywallSheet extends ConsumerStatefulWidget {
  const PaywallSheet({super.key, this.reason, this.feature, this.headline});
  final SkyEvent? reason;

  /// The line under the logo, when what brought them here says it better
  /// (a storm tonight, a sight they missed).
  final String? headline;

  /// What they tapped that's LookUp+ (Where to go, a later night…), so the
  /// sheet opens on that rather than on alerts.
  final PlusFeature? feature;
  @override
  ConsumerState<PaywallSheet> createState() => _PaywallState();
}

class _PaywallState extends ConsumerState<PaywallSheet> {
  List<PlusOffer>? _offers;

  /// What just happened, in plain words (a purchase that didn't go
  /// through, what Restore found), shown by the buttons. The plans stay.
  String? _note;
  bool _busy = false;
  String _chosen = PlusProducts.yearly;
  StreamSubscription<String>? _errors;

  @override
  void initState() {
    super.initState();
    _loadOffers();
    // The store reports a failed or declined purchase here, not from buy().
    _errors = ref.read(plusServiceProvider).errors.listen((_) {
      if (mounted) setState(() => _note = _notBought);
    });
  }

  static const _notBought = 'That didn\'t go through, and you haven\'t been charged. You can try again.';

  void _loadOffers() {
    setState(() => _offers = null);
    ref.read(plusServiceProvider).offers().then((o) {
      if (!mounted) return;
      setState(() {
        _offers = o;
        if (o.isNotEmpty && !o.any((x) => x.id == _chosen)) _chosen = o.first.id;
      });
    }).catchError((_) {
      // No store to ask: said in words below, with a way to try again.
      if (mounted) setState(() => _offers = const []);
    });
  }

  @override
  void dispose() {
    _errors?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    // Once they've bought it (or Restore found it), take them back to where
    // they were. Only on the change: a subscriber who opened this to manage
    // their plan keeps it open.
    ref.listen(settingsProvider, (prev, next) {
      if (prev?.value == null) return; // settings still loading: not a change
      if (!prev!.value!.isPlus && (next.value?.isPlus ?? false)) Navigator.of(context).maybePop();
    });
    final settings = ref.watch(settingsProvider).value;
    final isPlus = settings?.isPlus ?? false;
    final lead = settings?.leadMinutes ?? 10;
    final events = ref.watch(homeProvider).value?.events ?? const <SkyEvent>[];
    final ahead = AlertPlanner.plusOnlyAhead(events, DateTime.now());
    // The notification to show: the one that brought them here, else the
    // next Plus-only thing really coming over them.
    final preview = widget.reason ?? ahead.firstOrNull;
    final rest = ahead.where((e) => e.id != preview?.id).take(1).toList();
    final offers = _offers;
    final chosen = offers?.where((o) => o.id == _chosen).firstOrNull;
    final store = Theme.of(context).platform == TargetPlatform.iOS ? 'App Store' : 'Google Play';
    // Opened from a locked alert: say it's this one that needs LookUp+.
    final locked = widget.reason != null && widget.feature == null && widget.headline == null ? widget.reason : null;
    final headline = widget.headline ??
        (locked == null ? null : _lockedHeadline(locked)) ??
        switch (widget.feature) {
          PlusFeature.whereToGo => 'Clear, dark skies near you. Go.',
          PlusFeature.planAhead => 'Plan any of the next 14 nights.',
          PlusFeature.places => 'Save every place you love.',
          PlusFeature.transits => 'The station across the Sun or Moon.',
          PlusFeature.camera => 'The Pro camera. Sky settings, solved.',
          PlusFeature.noCaption => 'Photos with just the sky.',
          _ => 'Never miss the next event.',
        };
    // 1 Hook and proof (scrolls) · 2 Plan and the one button (pinned) · 3 Reassurance (under the button).
    final proof = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Text('LookUp', style: display(32, weight: FontWeight.w800)),
            Text('+', style: display(32, weight: FontWeight.w800, color: LookUpColors.blue)),
          ]),
          const SizedBox(height: 4),
          Text(headline, style: t.bodyLarge?.copyWith(color: LookUpColors.grey, fontSize: 17)),
          const SizedBox(height: 16),
          _NotificationPreview(event: preview, leadMinutes: lead),
          const SizedBox(height: 8),
          Text(
            preview == null
                ? 'Example alert'
                : locked != null
                    ? 'Free won\'t alert you to this one. ${fmtDay(preview.start)}.'
                    : 'Your next one: ${fmtDay(preview.start)}, ${fmtTime(preview.start.subtract(Duration(minutes: lead)))}',
            textAlign: TextAlign.center,
            style: t.bodySmall?.copyWith(color: LookUpColors.greyDim),
          ),
          const SizedBox(height: 16),
          PlusPerkGrid(detailed: true, except: {'alerts', widget.feature == PlusFeature.noCaption ? 'transits' : 'noCaption'}),
          if (rest.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Kicker('Also coming over you'),
            const SizedBox(height: 8),
            GroupedList(indent: 60, children: [for (final e in rest) _AheadRow(e)]),
          ],
          if (isPlus) ...[
            const SizedBox(height: 18),
            const Text('You have LookUp+. Thank you.', textAlign: TextAlign.center, style: TextStyle(color: LookUpColors.grey)),
            // Where to change or cancel it: the store's own page.
            TextButton(
              key: const Key('manage-subscription'),
              onPressed: () => openLink(context, manageSubscriptionUri),
              child: const Text('Manage or cancel'),
            ),
          ] else
            TextButton(
              key: const Key('restore-purchases'),
              onPressed: _busy ? null : _restore,
              child: const Text('Restore purchases'),
            ),
          const LegalLinks(),
        ],
      ),
    );

    final Widget buy = isPlus
        ? const SizedBox.shrink()
        : Container(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
            decoration: const BoxDecoration(
              color: LookUpColors.panel,
              border: Border(top: BorderSide(color: LookUpColors.line)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (offers == null)
                const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
              else if (offers.isEmpty) ...[
                Text(
                  'Can\'t reach the $store right now.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: LookUpColors.grey),
                ),
                TextButton(key: const Key('offers-retry'), onPressed: _loadOffers, child: const Text('Try again')),
              ] else ...[
                IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (final (i, o) in offers.indexed) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(
                        child: _PlanCard(
                          offer: o,
                          selected: o.id == _chosen,
                          monthly: offers.where((x) => x.id == PlusProducts.monthly).firstOrNull,
                          onTap: _busy ? null : () => setState(() => _chosen = o.id),
                        ),
                      ),
                    ],
                  ]),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('paywall-buy'),
                  onPressed: _busy || chosen == null ? null : () => _buy(chosen),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  child: Text(
                    switch (chosen?.id) {
                      PlusProducts.yearly => 'Try 7 days free',
                      _ => 'Continue · ${chosen?.price ?? ''} a month',
                    },
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  chosen?.id == PlusProducts.yearly
                      ? 'Then ${chosen!.price} a year. We\'ll remind you on day 5. Cancel any time in your $store account.'
                      : 'Renews monthly. Cancel any time in your $store account.',
                  textAlign: TextAlign.center,
                  style: t.bodySmall?.copyWith(color: LookUpColors.greyDim),
                ),
              ],
              if (_note != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(_note!, key: const Key('paywall-note'), textAlign: TextAlign.center, style: const TextStyle(color: LookUpColors.warn, height: 1.35)),
                  ),
                ),
            ]),
          );

    return SafeArea(
      child: Starfield(
        density: 0.00012,
        maxOpacity: 0.45,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: proof),
          buy,
        ]),
      ),
    );
  }

  Future<void> _buy(PlusOffer o) async {
    setState(() {
      _busy = true;
      _note = null;
    });
    try {
      await ref.read(plusServiceProvider).buy(o);
    } catch (_) {
      if (mounted) setState(() => _note = _notBought);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Restore purchases, and say what it found: silence reads as broken.
  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _note = null;
    });
    String? said;
    try {
      await ref.read(plusServiceProvider).restore();
      final has = (await ref.read(settingsProvider.future)).isPlus;
      final store = defaultTargetPlatform == TargetPlatform.iOS ? 'Apple ID' : 'Google account';
      said = has ? null : 'No LookUp+ found on this $store. If you bought it on another one, sign in with that and try again.';
    } catch (_) {
      said = 'Couldn\'t reach the store just now. Try again in a moment.';
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _note = said;
        });
      }
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
    final body = e == null ? 'Find a dark spot and look north.' : AlertPlanner.headsUpBody(e, miles: displayMiles);
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

/// One plan, as a card you pick before the single button below.
class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.offer, required this.selected, required this.onTap, this.monthly});
  final PlusOffer offer;
  final bool selected;
  final VoidCallback? onTap;
  final PlusOffer? monthly;

  @override
  Widget build(BuildContext context) {
    final yearly = offer.id == PlusProducts.yearly;
    final note = yearly ? _perMonth(offer) : null;
    final save = yearly ? _saving(offer, monthly) : null;
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
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(yearly ? 'Yearly' : 'Monthly', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                if (save != null) Pill(save, color: LookUpColors.blue),
              ]),
              const SizedBox(height: 4),
              Text(offer.price, style: numeric(size: 18, weight: FontWeight.w700)),
              Text(note ?? offer.cadence, style: const TextStyle(fontSize: 12.5, color: LookUpColors.grey)),
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
