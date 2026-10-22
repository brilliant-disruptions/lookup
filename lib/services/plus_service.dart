/// LookUp+ via the stores (StoreKit 2 on iOS, Play Billing on Android)
/// through the official `in_app_purchase` plugin.
///
/// Honest scope: entitlement is trusted from the store's purchase stream and
/// cached locally. There is no server-side receipt validation yet; add it
/// (RevenueCat or a Supabase edge function) before scaling paid.
library;

import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

abstract final class PlusProducts {
  static const monthly = 'lookup_plus_monthly';
  static const yearly = 'lookup_plus_yearly';
  static const lifetime = 'lookup_plus_lifetime';
  static const all = {monthly, yearly, lifetime};
}

class PlusOffer {
  const PlusOffer({required this.id, required this.title, required this.price, required this.details});
  final String id;
  final String title;
  final String price;
  final ProductDetails details;

  String get cadence => switch (id) {
        PlusProducts.monthly => 'per month',
        PlusProducts.yearly => 'per year',
        _ => 'once, forever',
      };
}

class PlusService {
  PlusService({InAppPurchase? iap, required this.onEntitlementChanged})
      : _iap = iap ?? InAppPurchase.instance;

  final InAppPurchase _iap;

  /// Called with `true` when any LookUp+ product is purchased or restored.
  final void Function(bool isPlus) onEntitlementChanged;

  StreamSubscription<List<PurchaseDetails>>? _sub;
  final _errors = StreamController<String>.broadcast();
  Stream<String> get errors => _errors.stream;

  Future<void> start() async {
    _sub ??= _iap.purchaseStream.listen(_onPurchases, onError: (e) => _errors.add('$e'));
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    await _errors.close();
  }

  Future<bool> get isAvailable => _iap.isAvailable();

  Future<List<PlusOffer>> offers() async {
    if (!await _iap.isAvailable()) return const [];
    final res = await _iap.queryProductDetails(PlusProducts.all);
    final order = [PlusProducts.yearly, PlusProducts.monthly, PlusProducts.lifetime];
    final list = [
      for (final p in res.productDetails)
        PlusOffer(id: p.id, title: p.title, price: p.price, details: p),
    ]..sort((a, b) => order.indexOf(a.id).compareTo(order.indexOf(b.id)));
    return list;
  }

  Future<void> buy(PlusOffer offer) async {
    await _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: offer.details));
  }

  Future<void> restore() => _iap.restorePurchases();

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          if (PlusProducts.all.contains(p.productID)) onEntitlementChanged(true);
        case PurchaseStatus.error:
          _errors.add(p.error?.message ?? 'Purchase failed');
        case PurchaseStatus.canceled:
        case PurchaseStatus.pending:
          break;
      }
      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
    }
  }
}
