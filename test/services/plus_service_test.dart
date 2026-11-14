import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:lookup/data/local_store.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/plus/plus_grant.dart';
import 'package:lookup/services/plus_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// The App Store as the plugin shows it (in_app_purchase_storekit 0.4.15,
/// StoreKit 2): a restore answers on the purchase stream with one list of
/// what the account owns now, every entry "restored", empty when there is
/// nothing; the list can land before or after the restore call returns.
/// Anything StoreKit hands over by itself (a renewal, a refund) arrives
/// alone, as "purchased".
class _Store implements InAppPurchase {
  final _stream = StreamController<List<PurchaseDetails>>.broadcast();

  /// What a restore lists. Null: the store can't be asked.
  List<PurchaseDetails>? owns = [];

  /// Whether the list lands after the restore call has returned.
  bool late = false;

  /// Never answers at all.
  bool silent = false;

  int restores = 0;
  final completed = <String>[];

  void send(List<PurchaseDetails> list) => _stream.add(list);

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _stream.stream;

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restores++;
    final list = owns;
    if (list == null) throw Exception('store unavailable');
    if (silent) return;
    if (late) {
      Timer(const Duration(milliseconds: 20), () => send(list));
    } else {
      send(list);
    }
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async => completed.add(purchase.productID);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _now = DateTime.utc(2026, 11, 14, 21);

PurchaseDetails _tx(
  String product, {
  PurchaseStatus status = PurchaseStatus.restored,
  Duration? endsIn,
  bool revoked = false,
  bool pending = false,
}) {
  final json = [
    '"productId":"$product"',
    if (endsIn != null) '"expiresDate":${_now.add(endsIn).millisecondsSinceEpoch}',
    if (revoked) '"revocationDate":${_now.millisecondsSinceEpoch - 1000}',
  ].join(',');
  return PurchaseDetails(
    productID: product,
    status: status,
    transactionDate: '${_now.millisecondsSinceEpoch}',
    verificationData: PurchaseVerificationData(
      localVerificationData: '{$json}',
      serverVerificationData: 'jws',
      source: 'app_store',
    ),
  )..pendingCompletePurchase = pending;
}

void main() {
  late _Store store;
  late List<PlusNews> news;
  late PlusService plus;

  setUp(() {
    store = _Store();
    news = [];
    plus = PlusService(
      iap: store,
      onNews: news.add,
      answerWait: const Duration(milliseconds: 200),
      now: () => _now,
    );
  });

  tearDown(() => plus.dispose());

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 60));

  group('asking the store at launch', () {
    test('a running subscription is LookUp+ until its period ends', () async {
      store.owns = [_tx(PlusProducts.monthly, endsIn: const Duration(days: 12))];
      await plus.start();
      await settle();
      expect(store.restores, 1, reason: 'start asks by itself');
      expect(news.single, isA<PlusOwned>().having((o) => o.until, 'until', _now.add(const Duration(days: 12))));
    });

    test('the lifetime purchase has no end, whatever else is owned', () async {
      store.owns = [
        _tx(PlusProducts.yearly, endsIn: const Duration(days: 40)),
        _tx(PlusProducts.lifetime),
      ];
      await plus.start(check: false);
      await plus.recheck();
      expect(news.single, isA<PlusOwned>().having((o) => o.until, 'until', isNull));
    });

    test('nothing owned (a trial cancelled and run out, a lapsed month) is said plainly', () async {
      await plus.start(check: false);
      await plus.recheck();
      expect(news.single, isA<PlusNotListed>());
    });

    test('someone else\'s product is not LookUp+', () async {
      store.owns = [_tx('another_app_pro')];
      await plus.start(check: false);
      await plus.recheck();
      expect(news.single, isA<PlusNotListed>());
    });

    test('the answer landing after the call returns is still the answer', () async {
      store
        ..late = true
        ..owns = [_tx(PlusProducts.yearly, endsIn: const Duration(days: 200))];
      await plus.start(check: false);
      await plus.recheck();
      expect(news.single, isA<PlusOwned>(), reason: 'never "nothing owned" just because the list was slow');
    });

    test('still in the store\'s list past its date (billing grace) counts from now', () async {
      store.owns = [_tx(PlusProducts.monthly, endsIn: const Duration(days: -2))];
      await plus.start(check: false);
      await plus.recheck();
      expect(news.single, isA<PlusOwned>().having((o) => o.until, 'until', _now));
    });

    test('a store that can\'t be asked changes nothing', () async {
      store.owns = null;
      await plus.start(check: false);
      await plus.recheck();
      expect(news, isEmpty);
    });

    test('nor does one that never answers', () async {
      store.silent = true;
      await plus.start(check: false);
      await plus.recheck();
      expect(news, isEmpty);
    });

    test('nor one that answers with an error', () async {
      await plus.start(check: false);
      store.silent = true;
      final check = plus.recheck();
      store.send([_tx(PlusProducts.monthly, status: PurchaseStatus.error)]);
      await check;
      expect(news, isEmpty);
    });

    test('asking twice at once is one question', () async {
      store.late = true;
      await plus.start(check: false);
      await Future.wait([plus.recheck(), plus.recheck(), plus.restore()]);
      expect(store.restores, 1);
      expect(news, hasLength(1));
    });

    test('nothing is asked before start or after dispose', () async {
      await plus.recheck();
      expect(store.restores, 0);
      await plus.start(check: false);
      await plus.dispose();
      await plus.recheck();
      expect(store.restores, 0);
      expect(news, isEmpty);
    });
  });

  group('what the store sends by itself', () {
    test('a purchase turns LookUp+ on and is finished', () async {
      await plus.start(check: false);
      store.send([
        _tx(PlusProducts.yearly, status: PurchaseStatus.purchased, endsIn: const Duration(days: 7), pending: true),
      ]);
      await settle();
      expect(news.single, isA<PlusOwned>().having((o) => o.until, 'until', _now.add(const Duration(days: 7))));
      expect(store.completed, [PlusProducts.yearly]);
      expect(store.restores, 0);
    });

    test('a refund: the store is asked, and with nothing left LookUp+ is taken back', () async {
      await plus.start(check: false);
      store.send([
        _tx(PlusProducts.lifetime, status: PurchaseStatus.purchased, revoked: true, pending: true),
      ]);
      await settle();
      expect(store.restores, 1);
      expect(news.single, isA<PlusRevoked>());
      expect(store.completed, [PlusProducts.lifetime], reason: 'still finished, or StoreKit sends it again');
    });

    test('a refund of one plan while another is still owned keeps LookUp+', () async {
      store.owns = [_tx(PlusProducts.lifetime)];
      await plus.start(check: false);
      store.send([
        _tx(PlusProducts.monthly, status: PurchaseStatus.purchased, endsIn: const Duration(days: 9), revoked: true),
      ]);
      await settle();
      expect(news.single, isA<PlusOwned>());
    });

    test('an old period delivered late grants nothing; the store is asked instead', () async {
      await plus.start(check: false);
      store.send([
        _tx(PlusProducts.monthly, status: PurchaseStatus.purchased, endsIn: const Duration(days: -40), pending: true),
      ]);
      await settle();
      expect(store.restores, 1);
      expect(news.single, isA<PlusNotListed>());
    });

    test('cancelled, pending and other apps\' purchases say nothing', () async {
      await plus.start(check: false);
      store.send([_tx(PlusProducts.monthly, status: PurchaseStatus.canceled)]);
      store.send([_tx(PlusProducts.monthly, status: PurchaseStatus.pending)]);
      store.send([_tx('another_app_pro', status: PurchaseStatus.purchased)]);
      await settle();
      expect(news, isEmpty);
      expect(store.restores, 0);
    });

    test('a failed purchase is reported to the paywall', () async {
      await plus.start(check: false);
      final errors = <String>[];
      plus.errors.listen(errors.add);
      store.send([_tx(PlusProducts.monthly, status: PurchaseStatus.error)]);
      await settle();
      expect(errors, ['Purchase failed']);
      expect(news, isEmpty);
    });
  });

  group('in the background refresh', () {
    late LocalStore prefs;

    setUp(() {
      SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
      prefs = LocalStore(SharedPreferencesAsync());
    });

    Future<void> save(LookUpSettings s) => prefs.saveSettings(s);

    test('a renewal is read, so the alerts keep coming with the app never opened', () async {
      final soon = DateTime.now().toUtc().add(const Duration(hours: 3));
      await save(LookUpSettings(isPlus: true, plusUntil: soon, plusSeenAt: soon.subtract(const Duration(days: 30))));
      final renewed = DateTime.now().toUtc().add(const Duration(days: 31));
      store.owns = [
        PurchaseDetails(
          productID: PlusProducts.monthly,
          status: PurchaseStatus.restored,
          transactionDate: null,
          verificationData: PurchaseVerificationData(
            localVerificationData: '{"expiresDate":${renewed.millisecondsSinceEpoch}}',
            serverVerificationData: 'jws',
            source: 'app_store',
          ),
        ),
      ];
      await confirmPlusInBackground(prefs, iap: store, supported: true);
      final s = await prefs.loadSettings();
      expect(s.isPlus, isTrue);
      expect(s.plusUntil!.difference(renewed).inSeconds.abs(), lessThan(2));
    });

    test('one that had already run out by the clock comes back when the renewal is read', () async {
      final ended = DateTime.now().toUtc().subtract(PlusGrant.grace + const Duration(days: 2));
      await save(LookUpSettings(isPlus: true, plusUntil: ended, plusSeenAt: ended.subtract(const Duration(days: 30))));
      expect((await prefs.loadSettings()).isPlus, isFalse, reason: 'run out for every reader');
      store.owns = [_txEnding(DateTime.now().toUtc().add(const Duration(days: 20)))];
      await confirmPlusInBackground(prefs, iap: store, supported: true);
      expect((await prefs.loadSettings()).isPlus, isTrue);
    });

    test('an empty answer with nobody looking takes nothing away', () async {
      await save(LookUpSettings(isPlus: true, plusSeenAt: DateTime.now().toUtc().subtract(const Duration(days: 90))));
      await confirmPlusInBackground(prefs, iap: store, supported: true);
      expect(store.restores, 1);
      expect((await prefs.loadSettings()).isPlus, isTrue);
    });

    test('free phones, and other platforms, don\'t ask at all', () async {
      await confirmPlusInBackground(prefs, iap: store, supported: true);
      await save(const LookUpSettings(isPlus: true));
      await confirmPlusInBackground(prefs, iap: store, supported: false);
      expect(store.restores, 0);
    });

    test('a store that fails leaves the saved LookUp+ alone', () async {
      await save(const LookUpSettings(isPlus: true));
      store.owns = null;
      await confirmPlusInBackground(prefs, iap: store, supported: true);
      expect((await prefs.loadSettings()).isPlus, isTrue);
    });
  });
}

PurchaseDetails _txEnding(DateTime end) => PurchaseDetails(
      productID: PlusProducts.yearly,
      status: PurchaseStatus.restored,
      transactionDate: null,
      verificationData: PurchaseVerificationData(
        localVerificationData: '{"expiresDate":${end.millisecondsSinceEpoch}}',
        serverVerificationData: 'jws',
        source: 'app_store',
      ),
    );
