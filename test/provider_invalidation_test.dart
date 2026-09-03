import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/providers.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/features/accounts/payment_account_providers.dart';
import 'package:mm_pos/features/accounting/accounting_providers.dart';
import 'package:mm_pos/features/cash/cash_providers.dart';

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

  /// The till figure on Cash Register — the number an owner counts the
  /// drawer against at close. Same class of risk as the account balance, on
  /// the screen where a stale figure turns into a real cash variance.
  ///
  /// Note these rows use `DateTime.now()`, not a fixed past date:
  /// `expectedCash` folds only movements at/after `session.openedAt`, so a
  /// back-dated row would be correctly excluded and the assertion would fail
  /// for the wrong reason.
  group('expectedCashProvider recomputes for every table it folds', () {
    Future<({int before, int after})> tillAround(
      Future<void> Function() mutate,
    ) async {
      await container
          .read(cashSessionRepositoryProvider)
          .openSession(openingAmount: 30000);
      final sub = container.listen(
        expectedCashProvider,
        (_, _) {},
        fireImmediately: true,
      );
      // `expectedCash` is null until `currentCashSessionProvider`'s stream
      // has actually delivered the open session. Reading straight after
      // openSession() races that first emission and yields null, which would
      // make the baseline 0 and the assertion fail for a reason that has
      // nothing to do with the watch graph under test.
      int? before;
      for (var i = 0; i < 20 && before == null; i++) {
        await pumpEventQueue();
        before = await container.read(expectedCashProvider.future);
      }
      expect(before, isNotNull,
          reason: 'the open cash session never reached expectedCashProvider — '
              'test setup problem, not a watch-graph failure.');

      // Let the signal SETTLE before taking the baseline. Every one of the
      // six streams `_CashInputSignal` listens to fires an initial emission
      // on subscription, and each one starts the debounce timer — so a
      // recompute is already pending here for reasons that have nothing to
      // do with the mutation below. Reading the baseline first and waiting
      // afterwards let that pending recompute pick up the mutation and made
      // this test pass even with the payments watch deleted (a false
      // negative that only showed up when the sabotage was checked).
      await Future<void>.delayed(kCashSignalDebounce * 3);
      await pumpEventQueue();
      before = await container.read(expectedCashProvider.future);
      await mutate();
      // The till signal is deliberately DEBOUNCED (`kCashSignalDebounce`,
      // "audit M7") so a burst of sales coalesces into one recompute — it
      // runs on a real `Timer`, which `pumpEventQueue()` does not advance.
      // So this waits actual time; no number of event-loop pumps would ever
      // fire it, and mistaking that for a missing watch is the trap here.
      await Future<void>.delayed(kCashSignalDebounce * 3);
      await pumpEventQueue();
      final after = await container.read(expectedCashProvider.future);
      sub.close();
      return (before: before!, after: after ?? 0);
    }

    test('a cash sale payment', () async {
      final r = await tillAround(() async {
        await db.into(db.payments).insert(PaymentsCompanion.insert(
              id: 'till-pay',
              shopId: shopId,
              saleId: 'sale-till',
              method: 'cash',
              amount: 7000,
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ));
      });
      expect(r.after, r.before + 7000,
          reason: 'expectedCashProvider is not watching payments — the till '
              'figure would sit stale while cash physically came in.');
    });

    test('a cash credit repayment', () async {
      final r = await tillAround(() async {
        await db.into(db.creditPayments).insert(CreditPaymentsCompanion.insert(
              id: 'till-repay',
              shopId: shopId,
              customerName: 'Aung',
              method: const Value('cash'),
              amount: 2500,
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ));
      });
      expect(r.after, r.before + 2500,
          reason: 'expectedCashProvider is not watching credit_payments.');
    });

    test('a cash expense', () async {
      final r = await tillAround(() async {
        await db.into(db.expenses).insert(ExpensesCompanion.insert(
              id: 'till-exp',
              shopId: shopId,
              category: 'other',
              amount: 1500,
              date: DateTime.now(),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ));
      });
      expect(r.after, r.before - 1500,
          reason: 'expectedCashProvider is not watching expenses.');
    });

    test('a cash supplier payment', () async {
      final r = await tillAround(() async {
        await db
            .into(db.supplierPayments)
            .insert(SupplierPaymentsCompanion.insert(
              id: 'till-suppay',
              shopId: shopId,
              supplierName: 'Golden Trading',
              method: const Value('cash'),
              amount: 900,
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ));
      });
      expect(r.after, r.before - 900,
          reason: 'expectedCashProvider is not watching supplier_payments.');
    });
  });

  /// The Balance Sheet composes almost every money figure in the app
  /// (account balances, till cash, stock at cost, receivables, payables,
  /// equity), so it inherits each of their watch graphs. A break anywhere
  /// upstream shows up here as a shop's net worth quietly not moving.
  group('balanceSheetProvider reflects upstream money movement', () {
    Future<({int before, int after})> assetsAround(
      Future<void> Function() mutate,
    ) async {
      final sub = container.listen(
        balanceSheetProvider,
        (_, _) {},
        fireImmediately: true,
      );
      // Same settle-first discipline as the till: this composes
      // cashInputSignalProvider, whose debounce fires on the initial
      // subscription emissions of every stream under it.
      await Future<void>.delayed(kCashSignalDebounce * 3);
      await pumpEventQueue();
      final before = (await container.read(balanceSheetProvider.future)).assets;
      await mutate();
      await Future<void>.delayed(kCashSignalDebounce * 3);
      await pumpEventQueue();
      final after = (await container.read(balanceSheetProvider.future)).assets;
      sub.close();
      return (before: before, after: after);
    }

    test('a payment into an account raises assets', () async {
      final r = await assetsAround(() async {
        await db.into(db.payments).insert(PaymentsCompanion.insert(
              id: 'bs-pay',
              shopId: shopId,
              saleId: 'bs-sale',
              method: accountId,
              amount: 4000,
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ));
      });
      expect(r.after, r.before + 4000,
          reason: 'the Balance Sheet did not follow the account balance — '
              'something in the chain from payments -> accountBalance -> '
              'balanceSheet stopped propagating.');
    });

    test('an expense paid from an account lowers assets', () async {
      final r = await assetsAround(() async {
        await db.into(db.expenses).insert(ExpensesCompanion.insert(
              id: 'bs-exp',
              shopId: shopId,
              category: 'other',
              amount: 1100,
              date: DateTime.now(),
              accountId: const Value(accountId),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ));
      });
      expect(r.after, r.before - 1100,
          reason: 'the Balance Sheet did not follow an account expense.');
    });
  });
}
