import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/providers.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/settings_repository.dart';
import 'package:mm_pos/features/accounts/payment_account_providers.dart';
import 'package:mm_pos/features/accounts/payment_account_repository.dart';
import 'package:mm_pos/features/equity/equity_providers.dart';

/// Regression tests for Riverpod-reactivity bugs — the class of bug where a
/// `FutureProvider` derives from several tables but only `ref.watch()`es an
/// invalidation signal for some of them, so the UI silently goes stale on a
/// write to the one it forgot, with no analyzer/test failure to catch it
/// (both `accountBalanceProvider` — fixed in changelog #44 — and
/// `cumulativeNetProfitProvider` — fixed in #45 — shipped exactly this bug).
/// Pure-logic unit tests elsewhere in this suite cannot catch this class of
/// bug at all, since the bug is in the provider's dependency graph, not in
/// any pure function. This file is the template for testing that pattern —
/// see CLAUDE.md's "ripple-effect check" for when to add one.
///
/// Uses a real `ProviderContainer` (not a widget), overriding only
/// [databaseProvider] with an in-memory Drift DB. [shopIdProvider] is left
/// as the real `StateProvider` so its `.notifier` can be driven directly.
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    container.read(shopIdProvider.notifier).state = 'shop-1';
  });

  tearDown(() async {
    container.dispose();
    // `overrideWithValue` bypasses databaseProvider's own `ref.onDispose(db.
    // close)`, so this in-memory DB needs closing explicitly.
    await db.close();
  });

  /// Listens to [provider] and resolves as soon as an emitted `AsyncData`
  /// satisfies [predicate] — avoids an arbitrary `Future.delayed` guess for
  /// "has the DB write's `watch()` stream propagated yet."
  Future<T> waitFor<T>(
    ProviderListenable<AsyncValue<T>> provider,
    bool Function(T) predicate,
  ) async {
    final completer = Completer<T>();
    final sub = container.listen(provider, (prev, next) {
      next.whenData((v) {
        if (!completer.isCompleted && predicate(v)) completer.complete(v);
      });
    }, fireImmediately: true);
    try {
      return await completer.future.timeout(const Duration(seconds: 5));
    } finally {
      sub.close();
    }
  }

  test(
      'accountBalanceProvider rebuilds when a SupplierPayment is recorded '
      'against this account (regression: #44, the KBZPay-balance-not-'
      'deducting bug)', () async {
    final repo =
        PaymentAccountRepository(db, 'shop-1', SettingsRepository(db));
    final accountId =
        await repo.upsertAccount(name: 'KBZPay', openingBalance: 10000);
    final account = (await repo.getAccount(accountId))!;

    final initial =
        await waitFor(accountBalanceProvider(account), (b) => b == 10000);
    expect(initial, 10000);

    await db.into(db.supplierPayments).insert(
          SupplierPaymentsCompanion.insert(
            id: 'sp1',
            shopId: 'shop-1',
            supplierName: 'Acme',
            amount: 4000,
            method: Value(accountId),
          ),
        );

    final afterPayment =
        await waitFor(accountBalanceProvider(account), (b) => b == 6000);
    expect(afterPayment, 6000); // 10000 opening − 4000 supplier payment
  });

  test(
      'cumulativeNetProfitProvider rebuilds when an Expense is recorded '
      '(regression: #45, Owner\'s Equity Retained Earnings staleness)',
      () async {
    final initial = await waitFor(cumulativeNetProfitProvider, (p) => p == 0);
    expect(initial, 0);

    await db.into(db.expenses).insert(
          ExpensesCompanion.insert(
            id: 'e1',
            shopId: 'shop-1',
            category: 'other',
            amount: 7000,
            date: DateTime.now(),
          ),
        );

    final afterExpense =
        await waitFor(cumulativeNetProfitProvider, (p) => p == -7000);
    expect(afterExpense, -7000);
  });
}
