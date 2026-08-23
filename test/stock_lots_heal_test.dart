import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/stock_lots.dart';

/// Regression tests for audit finding H4: the FIFO lot cache is derived
/// locally and was never rebuilt from movements pulled via sync — a second
/// device (or a fresh install / restore) computed COGS from empty or stale
/// lots. `consumeStockLots` now checks the lots against the movement
/// ledger's net and replays the ledger on mismatch before consuming.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  /// Inserts movements the way sync's `_stockMovements.upsertLocal` would:
  /// ledger rows only — no lots, no stock_levels (those are this device's
  /// own derived state).
  Future<void> seedForeignMovements() async {
    final now = DateTime.now();
    Future<void> movement(String id, int delta, int unitCost) async {
      await db.into(db.stockMovements).insert(StockMovementsCompanion.insert(
            id: id,
            shopId: 'shop-1',
            productId: 'p1',
            type: delta > 0 ? 'purchase' : 'sale',
            qtyDelta: delta,
            unitCost: Value(unitCost),
            createdAt: Value(now),
            updatedAt: Value(now),
          ));
    }

    await movement('m1', 10, 1000); // another device bought 10 @ 1000
    await movement('m2', -4, 1000); // and sold 4
  }

  test(
    'consumeStockLots replays pulled movements before consuming, so COGS '
    'comes from real lot costs, not the fallback price',
    () async {
      await seedForeignMovements();

      // Lots are empty (nothing local ever touched this product) — before
      // the heal, this consume would price BOTH units at the fallback cost.
      final cost = await consumeStockLots(db,
          productId: 'p1', qty: 2, fallbackUnitCost: 999);
      expect(cost, 2000, reason: '2 units from the 10@1000 lot');

      final lots = await (db.select(db.stockLots)
            ..where((t) => t.productId.equals('p1')))
          .get();
      expect(lots, hasLength(1));
      expect(lots.single.remainingQty, 4, reason: '10 opened - 2 sold - 4 foreign sale');
      expect(lots.single.unitCost, 1000);
    },
  );

  test('a fresh install replays the full ledger on first sale', () async {
    // Purchase 5 @ 2000, sell 2 (foreign), then purchase 5 @ 3000.
    final now = DateTime.now();
    Future<void> movement(String id, int delta, int unitCost) async {
      await db.into(db.stockMovements).insert(StockMovementsCompanion.insert(
            id: id,
            shopId: 'shop-1',
            productId: 'p1',
            type: delta > 0 ? 'purchase' : 'sale',
            qtyDelta: delta,
            unitCost: Value(unitCost),
            createdAt: Value(now),
            updatedAt: Value(now),
          ));
    }

    await movement('m1', 5, 2000);
    await movement('m2', -2, 2000);
    await movement('m3', 5, 3000);

    // FIFO across the replayed lots: 3 left @2000, then 5 @3000.
    final cost = await consumeStockLots(db,
        productId: 'p1', qty: 4, fallbackUnitCost: 999);
    expect(cost, 3 * 2000 + 1 * 3000);

    final lots = await db.select(db.stockLots).get();
    expect(lots, hasLength(1));
    expect(lots.single.remainingQty, 4);
    expect(lots.single.unitCost, 3000);
  });

  test('a consistent cache is left untouched (no pointless rebuild churn)',
      () async {
    // Build state through the live path: every consume is paired with a
    // movement, exactly as SalesRepository does — that's what keeps the
    // lots and the ledger sums equal.
    Future<void> movement(String id, int delta) async {
      await db.into(db.stockMovements).insert(StockMovementsCompanion.insert(
            id: id,
            shopId: 'shop-1',
            productId: 'p1',
            type: delta > 0 ? 'purchase' : 'sale',
            qtyDelta: delta,
            unitCost: const Value(500),
          ));
    }

    await pushStockLot(db, productId: 'p1', qty: 10, unitCost: 500);
    await movement('m1', 10);
    await consumeStockLots(db,
        productId: 'p1', qty: 3, fallbackUnitCost: 500);
    await movement('m2', -3);

    final before = await db.select(db.stockLots).get();
    expect(before, hasLength(1));
    expect(before.single.remainingQty, 7);

    // Consume again — sums match, so the same lot row (same seq) survives
    // untouched instead of being deleted and replayed.
    await consumeStockLots(db,
        productId: 'p1', qty: 1, fallbackUnitCost: 500);
    await movement('m3', -1);
    final after = await db.select(db.stockLots).get();
    expect(after.single.seq, before.single.seq,
        reason: 'no rebuild expected when lots already match the ledger');
    expect(after.single.remainingQty, 6);
  });
}
