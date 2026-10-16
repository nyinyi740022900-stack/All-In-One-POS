import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/providers.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/analytics_repository.dart';
import 'package:mm_pos/features/analytics/analytics_calculator.dart';
import 'package:mm_pos/features/analytics/analytics_providers.dart';

/// Counts `summary()` runs — each one is six queries on the database isolate.
class _CountingRepo extends AnalyticsRepository {
  _CountingRepo(super.db, super.shopId);
  int calls = 0;

  @override
  Future<AnalyticsSummary> summary(
    DateTime start,
    DateTime end, {
    Map<String, int> creditOwedBySaleId = const {},
  }) {
    calls++;
    return super.summary(start, end, creditOwedBySaleId: creditOwedBySaleId);
  }
}

/// The dashboard reads its tables through ONE debounced signal
/// (`analyticsInputSignalProvider`). These pin the two things that change
/// made true and the one it must not break:
/// - a sync pull landing ten batches recomputes once when it settles (the
///   old per-table watches recomputed — and re-showed the skeleton — ten
///   times);
/// - the first figure already applies repayments (Owed is never briefly the
///   raw unpaid difference);
/// - a write that arrives the way a sync pull writes (straight to the table)
///   still reaches the dashboard — the ripple-effect rule in CLAUDE.md.
void main() {
  const shopId = 'shop-1';
  late AppDatabase db;
  late ProviderContainer container;
  late _CountingRepo repo;
  final now = DateTime.now();

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        shopIdProvider.overrideWith((ref) => shopId),
        analyticsRepositoryProvider.overrideWith(
          (ref) => repo = _CountingRepo(ref.watch(databaseProvider), shopId),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> insertSale(
    String id, {
    int total = 1000,
    int paid = 1000,
    String? customer,
  }) => db
      .into(db.sales)
      .insert(
        SalesCompanion.insert(
          id: id,
          shopId: shopId,
          invoiceNo: 'INV-$id',
          total: Value(total),
          paid: Value(paid),
          customerName: Value(customer),
          finalizedAt: Value(now),
        ),
      );

  // The signal debounces on a real `Timer`, and a fixed `Future.delayed`
  // past it is no guarantee under a loaded full-suite run — the same trap
  // that flaked `provider_invalidation_test.dart`'s till case (2026-10-17).
  // So these wait on what happened rather than on the clock.
  const settleTimeout = Duration(seconds: 5);
  const pollEvery = Duration(milliseconds: 25);

  /// Waits until the signal has gone a full debounce window (plus the same
  /// again as margin) without bumping, then returns the summary that
  /// recompute produced. The caller keeps the provider subscribed (as the
  /// open screen does).
  Future<AnalyticsSummary> settled() async {
    var lastBump = DateTime.now();
    final sub = container.listen<int>(
      analyticsInputSignalProvider,
      (_, _) => lastBump = DateTime.now(),
    );
    try {
      final deadline = DateTime.now().add(settleTimeout);
      while (DateTime.now().difference(lastBump) <
          kAnalyticsSignalDebounce * 2) {
        if (DateTime.now().isAfter(deadline)) {
          fail('analyticsInputSignalProvider never settled.');
        }
        await Future<void>.delayed(pollEvery);
      }
      await pumpEventQueue();
    } finally {
      sub.close();
    }
    return container.read(analyticsSummaryProvider.future);
  }

  /// Re-reads the summary until [done] holds, giving up after
  /// [settleTimeout] and returning the last (stale) value — so a missing
  /// watch still fails the caller's `expect`, just not on a guessed delay.
  Future<AnalyticsSummary> until(bool Function(AnalyticsSummary) done) async {
    final deadline = DateTime.now().add(settleTimeout);
    var value = await container.read(analyticsSummaryProvider.future);
    while (!done(value) && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(pollEvery);
      value = await container.read(analyticsSummaryProvider.future);
    }
    return value;
  }

  test('a direct write (as a sync pull makes) reaches the dashboard', () async {
    final sub = container.listen(analyticsSummaryProvider, (_, _) {});
    addTearDown(sub.close);
    expect((await settled()).revenue, 0);

    await insertSale('a');
    expect((await until((s) => s.revenue != 0)).revenue, 1000);

    await db
        .into(db.expenses)
        .insert(
          ExpensesCompanion.insert(
            id: 'e1',
            shopId: shopId,
            category: 'rent',
            amount: 300,
            date: now,
          ),
        );
    expect((await until((s) => s.expenses != 0)).expenses, 300);
  });

  test(
    'pulled batches recompute once the pull settles, not per batch',
    () async {
      final sub = container.listen(analyticsSummaryProvider, (_, _) {});
      addTearDown(sub.close);
      await settled();
      final before = repo.calls;

      // A pull lands rows in batches with a network round trip between them;
      // each batch used to restart the summary on its own.
      for (var batch = 0; batch < 10; batch++) {
        await db.batch((b) {
          for (var i = 0; i < 4; i++) {
            b.insert(
              db.sales,
              SalesCompanion.insert(
                id: 'burst-$batch-$i',
                shopId: shopId,
                invoiceNo: 'INV-$batch-$i',
                total: const Value(1000),
                paid: const Value(1000),
                finalizedAt: Value(now),
              ),
            );
          }
        });
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      final after = await settled();

      expect(after.revenue, 40000);
      expect(after.salesCount, 40);
      expect(
        repo.calls - before,
        lessThanOrEqualTo(2),
        reason: 'ten pulled batches must not mean ten full recomputes',
      );
    },
  );

  test('the first figure already applies repayments to Owed', () async {
    await insertSale('credit', total: 1000, paid: 0, customer: 'Daw Hla');
    await db
        .into(db.creditPayments)
        .insert(
          CreditPaymentsCompanion.insert(
            id: 'r1',
            shopId: shopId,
            customerName: 'Daw Hla',
            amount: 400,
          ),
        );

    final first = await container.read(analyticsSummaryProvider.future);
    expect(first.creditOutstanding, 600);
    expect(first.collected, 400);
  });
}
