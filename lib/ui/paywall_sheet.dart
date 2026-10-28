import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/sky_event.dart';
import '../domain/plus/upgrade_moments.dart';
import '../services/plus_service.dart';
import '../state/providers.dart';
import 'format.dart';
import 'kit/kit.dart';
import 'theme.dart';

/// The paywall appears only when there's a concrete reason: a Plus-only
/// event actually coming for this user (spec §7), something they reached
/// for ([because], e.g. a second saved place), or from Settings.
Future<void> showPaywall(BuildContext context, {SkyEvent? reason, String? because}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PaywallSheet(reason: reason, because: because),
    );

/// The line under the title: why LookUp+, right now.
String paywallLine(SkyEvent? r, String? because) {
  if (because != null) return because;
  if (r == null) return 'Every reason to step outside, not just the station.';
  return switch (r.type) {
    SkyEventType.favourite =>
      '${r.details['name']} is at its best ${fmtDay(r.start).toLowerCase()} at ${fmtTime(r.start)}. LookUp+ taps you when it\'s time.',
    SkyEventType.milkyWayNight => r.details['here'] == true
        ? 'It\'s a Milky Way night here ${fmtDay(r.start).toLowerCase()}. LookUp+ taps you when it\'s dark enough.'
        : 'It\'s a Milky Way night at ${r.details['place']} ${fmtDay(r.start).toLowerCase()}. LookUp+ tells you in time to get there.',
    _ => '${eventTitle(r)} passes over you ${fmtDay(r.start).toLowerCase()} at ${fmtTime(r.start)}. LookUp+ taps you 10 minutes before.',
  };
}

/// One tappable line offering LookUp+ where it would help ("Get a tap 10
/// minutes before"). Shows nothing once they have it.
class PlusNudge extends ConsumerWidget {
  const PlusNudge(this.text, {super.key, this.reason, this.because});
  final String text;
  final SkyEvent? reason;
  final String? because;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(settingsProvider).value?.isPlus ?? false) return const SizedBox.shrink();
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: () => showPaywall(context, reason: reason, because: because),
        behavior: HitTestBehavior.opaque,
        child: Row(children: [
          const Pill('LookUp+', color: LookUpColors.blue),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14, color: LookUpColors.white))),
          const Icon(Icons.arrow_forward_rounded, size: 18, color: LookUpColors.blue),
        ]),
      ),
    );
  }
}

/// After they've logged a sighting: one quiet offer, only for people really
/// using the app and at most weekly (see [offerPlusAfterSighting]).
class PlusAfterSighting extends ConsumerStatefulWidget {
  const PlusAfterSighting({super.key});
  @override
  ConsumerState<PlusAfterSighting> createState() => _PlusAfterSightingState();
}

class _PlusAfterSightingState extends ConsumerState<PlusAfterSighting> {
  int? _seen;

  @override
  void initState() {
    super.initState();
    _decide();
  }

  // Decided once, so recording the ask doesn't make it vanish.
  Future<void> _decide() async {
    final s = await ref.read(settingsProvider.future);
    final log = await ref.read(skyLogProvider.future);
    final now = DateTime.now().toUtc();
    if (!offerPlusAfterSighting(s, seenCount: log.total, now: now) || !mounted) return;
    setState(() => _seen = log.total);
    await ref.read(settingsProvider.notifier).edit((s) => s.copyWith(lastPlusAskAt: now));
  }

  @override
  Widget build(BuildContext context) {
    final n = _seen;
    if (n == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: PlusNudge(
        'Want Starlink trains, aurora and your favourites too?',
        because: 'You\'ve seen ${n == 1 ? 'one thing' : '$n things'} with LookUp. '
            'LookUp+ taps you for everything else worth stepping out for.',
      ),
    );
  }
}

class PaywallSheet extends ConsumerStatefulWidget {
  const PaywallSheet({super.key, this.reason, this.because});
  final SkyEvent? reason;
  final String? because;
  @override
  ConsumerState<PaywallSheet> createState() => _PaywallState();
}

class _PaywallState extends ConsumerState<PaywallSheet> {
  List<PlusOffer>? _offers;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ref.read(plusServiceProvider).offers().then((o) {
      if (mounted) setState(() => _offers = o);
    }).catchError((e) {
      if (mounted) setState(() => _error = '$e');
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final isPlus = ref.watch(settingsProvider).value?.isPlus ?? false;
    final r = widget.reason;
    return SafeArea(
      child: Starfield(
        density: 0.00012,
        maxOpacity: 0.45,
        // Scrolls on short phones so the offers are always reachable.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Text('LookUp', style: display(36, weight: FontWeight.w800)),
                Text('+', style: display(36, weight: FontWeight.w800, color: LookUpColors.blue)),
              ]),
              const SizedBox(height: 8),
              Text(
                paywallLine(r, widget.because),
                style: t.bodyLarge?.copyWith(color: LookUpColors.grey, fontSize: 17),
              ),
              const SizedBox(height: 22),
              GroupedList(indent: 60, children: [
                for (final (glyph, line) in [
                  (EventGlyph.forType(SkyEventType.auroraNow, size: 32), 'Aurora alerts the moment it\'s happening, and a wake-me option'),
                  (EventGlyph.forType(SkyEventType.starlinkTrain, size: 32), 'Starlink trains, Tiangong and rocket launches you can see'),
                  (EventGlyph.forType(SkyEventType.favourite, size: 32), 'A tap when a favourite is at its best on a clear night'),
                  (EventGlyph.forType(SkyEventType.milkyWayNight, size: 32), 'Milky Way nights at your dark places'),
                  (const EventGlyph(icon: Icons.place_rounded, color: LookUpColors.violet, size: 32), 'All your places compared every night, two weeks of planning, and the home-screen widget'),
                ])
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Row(children: [
                      glyph,
                      const SizedBox(width: 12),
                      Expanded(child: Text(line, style: t.bodyMedium?.copyWith(height: 1.35))),
                    ]),
                  ),
              ]),
              const SizedBox(height: 20),
              if (isPlus)
                const Text('You have LookUp+. Thank you.', textAlign: TextAlign.center, style: TextStyle(color: LookUpColors.grey))
              else if (_error != null)
                Text(_error!, style: const TextStyle(color: LookUpColors.warn))
              else if (_offers == null)
                const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
              else if (_offers!.isEmpty)
                const Text(
                  'The store isn\'t reachable right now. Products appear once the app is set up in App Store Connect / Play Console.',
                  style: TextStyle(color: LookUpColors.grey),
                )
              else
                for (final o in _offers!)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _OfferButton(offer: o, busy: _busy, onTap: () => _buy(o), highlight: o.id == PlusProducts.yearly),
                  ),
              if (!isPlus)
                TextButton(
                  onPressed: _busy ? null : _restore,
                  child: const Text('Restore purchases'),
                ),
              const SizedBox(height: 4),
              Text(
                'Subscriptions renew automatically and can be cancelled any time in your store account. 7-day free trial on yearly.',
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

class _OfferButton extends StatelessWidget {
  const _OfferButton({required this.offer, required this.onTap, required this.busy, required this.highlight});
  final PlusOffer offer;
  final VoidCallback onTap;
  final bool busy;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final label = switch (offer.id) {
      PlusProducts.monthly => 'Monthly',
      PlusProducts.yearly => 'Yearly',
      _ => 'Lifetime',
    };
    final child = Row(children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      if (highlight) ...[
        const SizedBox(width: 10),
        const Pill('Best value', color: LookUpColors.blueInk),
      ],
      const Spacer(),
      Text(offer.price, style: numeric(size: 16, weight: FontWeight.w700, color: highlight ? LookUpColors.black : LookUpColors.white)),
      const SizedBox(width: 6),
      Text(offer.cadence, style: TextStyle(fontSize: 12.5, color: highlight ? LookUpColors.greyDim : LookUpColors.grey)),
    ]);
    const size = Size.fromHeight(58);
    return highlight
        ? FilledButton(onPressed: busy ? null : onTap, style: FilledButton.styleFrom(minimumSize: size), child: child)
        : OutlinedButton(onPressed: busy ? null : onTap, style: OutlinedButton.styleFrom(minimumSize: size), child: child);
  }
}
