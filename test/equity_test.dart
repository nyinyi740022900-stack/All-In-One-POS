import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/analytics_repository.dart';
import 'package:mm_pos/features/equity/equity_calculator.dart';

void main() {
  group('computeEquitySummary (pure)', () {
    EquityEntry entry(String type, int amount) => EquityEntry(
          id: 'eq-$type-$amount',
          shopId: 'shop-1',
          type: type,
          amount: amount,
          date: DateTime(2026, 7, 1),
          createdAt: DateTime(2026, 7, 1),
          updatedAt: DateTime(2026, 7, 1),
          isDeleted: false,
          dirty: false,
        );

    test('paid-in capital = contributions - drawings', () {
      final result = computeEquitySummary(
        entries: [
          entry(equityTypeContribution, 500000),
          entry(equityTypeDrawing, 100000),
        ],
        cumulativeNetProfit: 0,
      );
      expect(result.paidInCapital, 400000);
    });

    test('retained earnings passes cumulative net profit straight through', () {
      final result = computeEquitySummary(
        entries: const [],
        cumulativeNetProfit: 250000,
      );
      expect(result.retainedEarnings, 250000);
    });

    test('total equity = paid-in capital + retained earnings', () {
      final result = computeEquitySummary(
        entries: [entry(equityTypeContribution, 300000)],
        cumulativeNetProfit: 150000,
      );
      expect(result.totalEquity, 450000);
    });

    test('a net loss (negative cumulative profit) reduces total equity', () {
      final result = computeEquitySummary(
        entries: [entry(equityTypeContribution, 300000)],
        cumulativeNetProfit: -50000,
      );
      expect(result.totalEquity, 250000);
    });
  });

  group('cumulativeNetProfit (repository SQL aggregate — audit C2)', () {
    late AppDatabase db;
    late AnalyticsRepository repo;

    // Half-open window [start, end), mirroring summary()'s convention.
    final start = DateTime(2026, 7, 1);
    final end = DateTime(2026, 8, 1);

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = AnalyticsRepository(db, 'shop-1');
    });

    tearDown(() async => db.close());

    Future<void> seedProduct(
      String id,
      int cost, {
      bool deleted = false,
      String shop = 'shop-1',
    }) async {
      final t = DateTime(2026, 6, 1);
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: id,
            shopId: shop,
            name: 'P-$id',
            salePrice: const Value(100),
            costPrice: Value(cost),
            createdAt: Value(t),
            updatedAt: Value(t),
            isDeleted: Value(deleted),
          ));
    }

    Future<void> seedSale({
      required String id,
      required int total,
      required DateTime at,
      bool deleted = false,
    }) async {
      await db.into(db.sales).insert(SalesCompanion.insert(
            id: id,
            shopId: 'shop-1',
            invoiceNo: 'INV-$id',
            finalizedAt: Value(at),
            subtotal: Value(total),
            total: Value(total),
            paid: Value(total),
            isDeleted: Value(deleted),
          ));
    }

    Future<void> seedItem({
      required String id,
      required String saleId,
      required String productId,
      required int qty,
      int? costSnapshot,
    }) async {
      final t = DateTime(2026, 6, 1);
      await db.into(db.saleItems).insert(SaleItemsCompanion.insert(
            id: id,
            shopId: 'shop-1',
            saleId: saleId,
            productId: productId,
            nameSnapshot: 'item-$id',
            priceSnapshot: 100,
            qty: qty,
            lineTotal: 100 * qty,
            costSnapshot: Value(costSnapshot),
            createdAt: Value(t),
            updatedAt: Value(t),
          ));
    }

    Future<void> seedExpense(
      String id,
      int amount,
      DateTime date, {
      bool deleted = false,
    }) async {
      await db.into(db.expenses).insert(ExpensesCompanion.insert(
            id: id,
            shopId: 'shop-1',
            category: 'rent',
            amount: amount,
            date: date,
            isDeleted: Value(deleted),
          ));
    }

    Future<int> net() => repo.cumulativeNetProfit(start: start, end: end);

    test('empty ledger nets 0', () async {
      expect(await net(), 0);
    });

    test('matches hand-computed figure AND summary().netProfit exactly',
        () async {
      await seedProduct('p-live', 200);
      await seedProduct('p-dead', 90, deleted: true); // tombstoned still counts
      await seedSale(id: 'a', total: 1000, at: DateTime(2026, 7, 3));
      await seedItem(
          id: 'i1', saleId: 'a', productId: 'p-live', qty: 2, costSnapshot: 350);
      await seedItem(id: 'i2', saleId: 'a', productId: 'p-dead', qty: 1);
      // Refund = ordinary negated row.
      await seedSale(id: 'b', total: -300, at: DateTime(2026, 7, 4));
      // Deleted sale must be excluded entirely.
      await seedSale(id: 'c', total: 5000, at: DateTime(2026, 7, 5),
          deleted: true);
      await seedExpense('e1', 300, DateTime(2026, 7, 6));
      await seedExpense('e2', 999, DateTime(2026, 7, 7), deleted: true);
      await seedExpense('e3', 555, DateTime(2026, 8, 15)); // past `end`

      // revenue 1000 − 300; cost 350 + (fallback 90); expenses 300.
      const expected = 700 - 440 - 300;
      expect(await net(), expected);
      expect(
        await net(),
        (await repo.summary(start, end)).netProfit,
        reason: 'SQL aggregate must stay in exact parity with the trusted '
            'Dart-fold summary — this pins future schema/query drift',
      );
    });

    test('window bounds: start inclusive, end exclusive', () async {
      await seedSale(id: 'at-start', total: 100, at: start);
      await seedSale(id: 'at-end', total: 777, at: end);
      expect(await net(), 100);
    });

    test('a foreign-shop product contributes ZERO fallback cost (not its '
        'cost price)', () async {
      await seedProduct('p-fx', 500, shop: 'shop-2');
      await seedSale(id: 's', total: 400, at: DateTime(2026, 7, 10));
      await seedItem(id: 'si', saleId: 's', productId: 'p-fx', qty: 3);
      // summary()'s product map only holds THIS shop's rows, so the
      // fallback for a foreign-shop item is 0 — the JOIN must mirror that.
      expect(await net(), 400);
      expect(
        await net(),
        (await repo.summary(start, end)).netProfit,
      );
    });
  });
}
