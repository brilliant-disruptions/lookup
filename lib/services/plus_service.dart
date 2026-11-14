/// LookUp+ via the stores (StoreKit 2 on iOS, Play Billing on Android)
/// through the official `in_app_purchase` plugin.
///
/// The store decides, and is asked again: at a purchase, on every launch
/// and in the background refresh ([PlusService.recheck]). What it says goes
/// to `domain/plus/plus_grant.dart`, which saves LookUp+ with its end date
/// and lets it run out. On iPhone the question is StoreKit 2's current
/// entitlements, read on the phone with no sign-in prompt; expired and
/// refunded purchases aren't in it.
///
/// Honest scope: StoreKit checks each transaction's signature on the phone,
/// and that is all the checking there is. There is no server-side receipt
/// validation; add it (e.g. RevenueCat) before scaling paid.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:in_app_purchase/in_app_purchase.dart';

import '../data/local_store.dart';
import '../domain/plus/plus_grant.dart';

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
  PlusService({
    InAppPurchase? iap,
    required this.onNews,
    this.answerWait = const Duration(seconds: 8),
    DateTime Function()? now,
  })  : _iap = iap ?? InAppPurchase.instance,
        _now = now ?? (() => DateTime.now().toUtc());

  final InAppPurchase _iap;
  final DateTime Function() _now;

  /// Called with what the store says about LookUp+, each time it says it.
  final FutureOr<void> Function(PlusNews news) onNews;

  /// How long [recheck] waits for the store before giving up (and changing
  /// nothing).
  final Duration answerWait;

  StreamSubscription<List<PurchaseDetails>>? _sub;
  _Check? _check;
  var _closed = false;
  final _errors = StreamController<String>.broadcast();
  Stream<String> get errors => _errors.stream;

  /// Listens to the store and, unless [check] is off, asks it what the
  /// account owns without waiting for the answer.
  Future<void> start({bool check = true}) async {
    _sub ??= _iap.purchaseStream.listen(_onPurchases, onError: (Object e) {
      _check?.failed = true;
      if (!_errors.isClosed) _errors.add('$e');
    });
    if (check) unawaited(recheck());
  }

  Future<void> dispose() async {
    _closed = true;
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

  /// The Restore purchases button: the same question as [recheck].
  Future<void> restore() => recheck();

  /// Asks the store what this account owns right now and reports it:
  /// [PlusOwned] with the period's end, or [PlusNotListed] when the store
  /// answers with no LookUp+ ([PlusRevoked] when [afterRevoke], a refund
  /// having just come through).
  ///
  /// Silent on iPhone (StoreKit 2's current entitlements: no sign-in sheet).
  /// The answer comes on the purchase stream as one list, every entry
  /// "restored", empty when there is nothing. A store that can't be asked,
  /// or doesn't answer within [answerWait], changes nothing.
  Future<void> recheck({bool afterRevoke = false}) {
    if (_sub == null || _closed) return Future.value();
    final running = _check;
    if (running != null) {
      running.afterRevoke = running.afterRevoke || afterRevoke;
      return running.done.future;
    }
    final check = _check = _Check(afterRevoke);
    () async {
      try {
        await _iap.restorePurchases().timeout(answerWait);
        await check.answered.future.timeout(answerWait);
      } catch (_) {
        check.failed = true;
      }
      _check = null;
      if (!check.failed && !check.found && !_closed) {
        await _tell(check.afterRevoke ? const PlusRevoked() : const PlusNotListed());
      }
      check.done.complete();
    }();
    return check.done.future;
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    final now = _now();
    final check = _check;
    final answers = check != null &&
        !check.answered.isCompleted &&
        purchases.every((p) => p.status == PurchaseStatus.restored);

    var owned = false;
    var lifetime = false;
    DateTime? until;
    // A purchase that no longer counts came by itself (a refund, or an old
    // period delivered late): ask what is owned now.
    var revoked = false;
    var stale = false;
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          if (!PlusProducts.all.contains(p.productID)) break;
          final restored = p.status == PurchaseStatus.restored;
          final t = StoreTransaction.read(p.verificationData.localVerificationData);
          if (t.revoked) {
            revoked = true;
          } else if (!t.upgraded && (restored || t.activeAt(now))) {
            // "Restored" is the store's list of what is owned now: believed
            // even past the date (Apple's billing grace), from now.
            owned = true;
            final end = t.expires;
            if (end == null) {
              lifetime = true;
            } else {
              final e = end.isAfter(now) ? end : now;
              if (until == null || e.isAfter(until)) until = e;
            }
          } else {
            stale = true;
          }
        case PurchaseStatus.error:
          if (check != null) check.failed = true;
          if (!_errors.isClosed) _errors.add(p.error?.message ?? 'Purchase failed');
        case PurchaseStatus.canceled:
        case PurchaseStatus.pending:
          break;
      }
    }
    if (answers) {
      check.found = owned;
      check.answered.complete();
    }
    if (owned) await _tell(PlusOwned(until: lifetime ? null : until));
    if ((revoked || stale) && !owned) unawaited(recheck(afterRevoke: revoked));

    for (final p in purchases) {
      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
    }
  }

  Future<void> _tell(PlusNews news) async {
    try {
      await onNews(news);
    } catch (_) {
      // Saving failed: the next launch asks again.
    }
  }
}

/// One [PlusService.recheck] in flight.
class _Check {
  _Check(this.afterRevoke);
  bool afterRevoke;
  bool failed = false;
  bool found = false;
  final answered = Completer<void>();
  final done = Completer<void>();
}

/// The background refresh's look at the store (iPhone): a subscriber who
/// never opens the app still has their renewal read, so their alerts keep
/// coming. It only ever keeps LookUp+ going, or ends it on a refund: an
/// empty answer with nobody looking is left for the next launch, and a
/// subscription that really ended runs out by the clock
/// ([PlusGrant.asOf]). Best effort, and quiet when it can't be done.
Future<void> confirmPlusInBackground(LocalStore store, {InAppPurchase? iap, bool? supported}) async {
  if (!(supported ?? Platform.isIOS)) return;
  final done = Completer<void>();
  runZonedGuarded(() async {
    try {
      final s = await store.loadSettings();
      if (!s.isPlus && s.plusUntil == null) return;
      final svc = PlusService(
        iap: iap,
        answerWait: const Duration(seconds: 5),
        onNews: (news) async {
          if (news is PlusNotListed) return;
          final current = await store.loadSettings();
          final next = PlusGrant.apply(current, news, DateTime.now().toUtc());
          if (!identical(next, current)) await store.saveSettings(next);
        },
      );
      await svc.start(check: false);
      await svc.recheck();
      await svc.dispose();
    } catch (_) {
      // No store in this isolate: the saved LookUp+ stands until its date.
    } finally {
      if (!done.isCompleted) done.complete();
    }
  }, (_, _) {
    if (!done.isCompleted) done.complete();
  });
  return done.future;
}
