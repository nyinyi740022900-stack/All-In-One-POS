import 'package:drift/drift.dart';

import '../../domain/fifo_cost_calculator.dart';
import '../local/database.dart';

/// DB-backed wrappers around [consumeFifo] shared by [InventoryRepository]
/// (restocks/adjustments) and [SalesRepository] (sale/refund) — both talk to
/// [AppDatabase] directly rather than depending on each other, matching how
/// the rest of the stock-tracking logic in this codebase is split.

/// Opens a new lot (a purchase, opening balance, or positive stock
/// adjustment) for [productId] at [unitCost] per unit. No-op for `qty <= 0`.
Future<void> pushStockLot(
  AppDatabase db, {
  required String productId,
  required int qty,
  required int unitCost,
}) async {
  if (qty <= 0) return;
  await db.into(db.stockLots).insert(StockLotsCompanion.insert(
        productId: productId,
        remainingQty: qty,
        unitCost: unitCost,
      ));
}

/// Consumes [qty] units FIFO (oldest lot first) from [productId]'s open
/// lots, persisting the result (updating partially-consumed lots, deleting
/// exhausted ones). Returns the total cost — tracked units at their lot
/// cost, plus any shortfall (untracked legacy stock, or an oversell) priced
/// at [fallbackUnitCost]. No-op (returns 0) for `qty <= 0`.
Future<int> consumeStockLots(
  AppDatabase db, {
  required String productId,
  required int qty,
  required int fallbackUnitCost,
}) async {
  if (qty <= 0) return 0;

  final rows = await (db.select(db.stockLots)
        ..where((t) => t.productId.equals(productId))
        ..orderBy([(t) => OrderingTerm(expression: t.seq)]))
      .get();
  final lots = [
    for (final r in rows)
      FifoLot(id: r.seq, remainingQty: r.remainingQty, unitCost: r.unitCost)
  ];

  final result = consumeFifo(lots, qty);

  final keptById = {for (final l in result.remainingLots) l.id: l};
  for (final r in rows) {
    final kept = keptById[r.seq];
    if (kept == null) {
      await (db.delete(db.stockLots)..where((t) => t.seq.equals(r.seq))).go();
    } else if (kept.remainingQty != r.remainingQty) {
      await (db.update(db.stockLots)..where((t) => t.seq.equals(r.seq)))
          .write(StockLotsCompanion(remainingQty: Value(kept.remainingQty)));
    }
  }

  return result.totalCost + result.shortfall * fallbackUnitCost;
}
