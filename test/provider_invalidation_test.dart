import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/providers.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/features/accounts/payment_account_providers.dart';

/// Guards the "derived figure goes silently stale" bug class — the one
/// CLAUDE.md's ripple-effect check step 2 asks for by hand:
///
/// > If you added a FutureProvider/derived value that depends on a table,
/// > confirm it `ref.watch()`s an invalidation signal for **every** table it
/// > reads — not just the "obvious" one.
///
/// `accountBalanceProvider` folds four money tables but watched only
/// `salesStreamProvider` as a proxy for the payments side. Sales and their
/// payments arrive in *separate* sync-pull transactions, so a cross-device
/// payment left every account balance understated until some unrelated table
/// happened to refresh (#295-8). Nothing caught it: the pure fold
/// (`computeAccountBalance`, covered in `payment_account_test.dart`) was
/// always correct — it's the watch graph that was wrong, and a missing watch
/// makes the UI quietly stale rather than throwing.
///
/// So this drives the real provider through a container and writes to each
/// source table **directly**, bypassing the repositories — which is exactly
/// what a sync pull does. A repository call could invalidate providers
/// explicitly and hide the missing watch.
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  const shopId = 'shop-1';
  const accountId = 'acct-kbz';
  final at = DateTime(2026, 8, 1);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        shopIdProvider.overrideWith((ref) => shopId),
      ],
    );

    await db.into(db.paymentAccounts).insert(PaymentAccountsCompanion.insert(
          id: accountId,
          shopId: shopId,
          name: 'KBZPay',
          openingBalance: const Value(0),
          updatedAt: Value(at),
        ));
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<PaymentAccount> account() async =>
      (db.select(db.paymentAccounts)..where((a) => a.id.equals(accountId)))
          .getSingle();

  /// Writes [mutate] straight to the DB and returns the balance before and
  /// after, with the provider kept subscribed throughout so Riverpod
  /// actually propagates an invalidation (an unlistened provider is free to
  /// simply recompute on next read, which would pass even with no watch).
  Future<({int before, int after})> balanceAround(
    Future<void> Function() mutate,
  ) async {
    final acct = await account();
    final sub = container.listen(
      accountBalanceProvider(acct),
      (_, _) {},
      fireImmediately: true,
    );
    final before = await container.read(accountBalanceProvider(acct).future);
    await mutate();
    // Drift's stream queries deliver on a microtask; give Riverpod the same
    // turn of the event loop the UI would get.
    await pumpEventQueue();
    final after = await container.read(accountBalanceProvider(acct).future);
    sub.close();
    return (before: before, after: after);
  }

  group('accountBalanceProvider recomputes for every table it folds', () {
    test('a payment arriving on its own (the #295-8 regression)', () async {
      final r = await balanceAround(() async {
        await db.into(db.payments).insert(PaymentsCompanion.insert(
              id: 'pay-1',
              shopId: shopId,
              saleId: 'sale-1',
              method: accountId,
              amount: 5000,
              updatedAt: Value(at),
            ));
      });
      expect(r.after, r.before + 5000,
          reason: 'a payment landed in its own transaction (a sync pull) and '
              'the balance did not move — accountBalanceProvider is not '
              'watching the payments table.');
    });

    test('a credit repayment', () async {
      final r = await balanceAround(() async {
        await db.into(db.creditPayments).insert(CreditPaymentsCompanion.insert(
              id: 'repay-1',
              shopId: shopId,
              customerName: 'Aung',
              method: const Value(accountId),
              amount: 3000,
              updatedAt: Value(at),
            ));
      });
      expect(r.after, r.before + 3000,
          reason: 'accountBalanceProvider is not watching credit_payments.');
    });

    test('an expense paid from this account', () async {
      final r = await balanceAround(() async {
        await db.into(db.expenses).insert(ExpensesCompanion.insert(
              id: 'exp-1',
              shopId: shopId,
              category: 'other',
              amount: 1200,
              date: at,
              accountId: const Value(accountId),
              updatedAt: Value(at),
            ));
      });
      expect(r.after, r.before - 1200,
          reason: 'accountBalanceProvider is not watching expenses.');
    });

    test('a supplier payment from this account', () async {
      final r = await balanceAround(() async {
        await db
            .into(db.supplierPayments)
            .insert(SupplierPaymentsCompanion.insert(
              id: 'suppay-1',
              shopId: shopId,
              supplierName: 'Golden Trading',
              method: const Value(accountId),
              amount: 800,
              updatedAt: Value(at),
            ));
      });
      expect(r.after, r.before - 800,
          reason: 'accountBalanceProvider is not watching supplier_payments.');
    });
  });
}
