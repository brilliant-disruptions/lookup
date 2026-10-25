import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/sky_event.dart';
import '../services/plus_service.dart';
import '../state/providers.dart';
import 'fancy/foil_text.dart';
import 'fancy/ornament_rule.dart';
import 'fancy/starfield.dart';
import 'format.dart';
import 'theme.dart';

/// The paywall appears only when a Plus-only event is actually coming for
/// this user (spec §7), or from Settings.
Future<void> showPaywall(BuildContext context, {SkyEvent? reason}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PaywallSheet(reason: reason),
    );

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

  @override
  void initState() {
    super.initState();
    ref.read(analyticsProvider).log('paywall_shown', {if (widget.reason != null) 'reason': widget.reason!.type.name});
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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                FoilText('LookUp', style: displaySerif(context, size: 40, weight: FontWeight.w600), gold: true),
                Text('+', style: displaySerif(context, size: 40, weight: FontWeight.w700, color: LookUpColors.blue)),
              ]),
              const SizedBox(height: 4),
              Text(
                r == null
                    ? 'Every reason to step outside, not just the station.'
                    : '${eventTitle(r)} passes over you ${fmtDay(r.start).toLowerCase()} at ${fmtTime(r.start)}. LookUp+ taps you 10 minutes before.',
                style: displaySerif(context, size: 24, weight: FontWeight.w500, italic: true, color: LookUpColors.grey, height: 1.15),
              ),
              const SizedBox(height: 18),
              const OrnamentRule(label: 'Included'),
              const SizedBox(height: 12),
              for (final line in const [
                'Aurora alerts the moment it is happening, and a wake-me option',
                'Starlink trains for two weeks after every launch',
                'Tiangong flyovers',
                'The one-minute "go outside now" nudge',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Padding(padding: EdgeInsets.only(top: 7), child: Icon(Icons.circle, size: 5, color: LookUpColors.blue)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(line, style: t.bodyMedium?.copyWith(height: 1.35))),
                  ]),
                ),
              const SizedBox(height: 10),
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
      await ref.read(analyticsProvider).log('purchase_started', {'product': o.id});
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
      Text(label, style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1.2)),
      if (highlight) ...[
        const SizedBox(width: 8),
        const Eyebrow('Best value', color: LookUpColors.blue),
      ],
      const Spacer(),
      Text(offer.price, style: monoData(context, size: 15, weight: FontWeight.w600, color: highlight ? LookUpColors.black : LookUpColors.white)),
      const SizedBox(width: 6),
      Text(offer.cadence, style: TextStyle(fontSize: 12, color: highlight ? LookUpColors.greyDim : LookUpColors.grey)),
    ]);
    return highlight
        ? FilledButton(onPressed: busy ? null : onTap, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)), child: child)
        : OutlinedButton(onPressed: busy ? null : onTap, style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)), child: child);
  }
}
