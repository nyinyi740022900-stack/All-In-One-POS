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

/// Rebuilds [productId]'s FIFO lots from scratch by replaying the
/// (append-only, synced) `stock_movements` ledger chronologically —
/// positive deltas open lots at the movement's `unitCost`, negative deltas
/// consume oldest-first. This is the exact derivation the live write paths
/// perform incrementally (see [pushStockLot]/[consumeStockLots] callers), so
/// replaying the full ledger reproduces the state those paths would have
/// produced — healing every way the cache can drift: movements pulled from
/// another device, a fresh install, a backup restore, or a missed sync.
Future<void> rebuildStockLots(AppDatabase db, String productId) async {
  final movements = await (db.select(db.stockMovements)
        ..where((m) =>
            m.productId.equals(productId) & m.isDeleted.equals(false))
        ..orderBy([
          // Chronological, with rowid as the exact tie-breaker for
          // same-second movements — same ordering the history view uses.
          (m) => OrderingTerm(expression: m.createdAt),
          (_) => OrderingTerm(
              expression: const CustomExpression<int>('rowid')),
        ]))
      .get();

  await db.transaction(() async {
    await (db.delete(db.stockLots)
          ..where((t) => t.productId.equals(productId)))
        .go();
    for (final m in movements) {
      if (m.qtyDelta > 0) {
        await pushStockLot(db,
            productId: productId, qty: m.qtyDelta, unitCost: m.unitCost);
      } else if (m.qtyDelta < 0) {
        // Consume without the fallback cost — a replay shortfall means the
        // ledger itself sells more than it ever bought; the lots can't
        // represent that, and the caller's own fallback pricing (product
        // cost at sale time) is what the live path would have used anyway.
        await _consumeOnly(db, productId: productId, qty: -m.qtyDelta);
      }
    }
  });
}

/// Consumes [qty] units FIFO (oldest lot first) from [productId]'s open
/// lots, persisting the result (updating partially-consumed lots, deleting
/// exhausted ones). Returns the total cost — tracked units at their lot
/// cost, plus any shortfall (untracked legacy stock, or an oversell) priced
/// at [fallbackUnitCost]. No-op (returns 0) for `qty <= 0`.
///
/// Before consuming, the cached lots are checked against the movement
/// ledger's net (cheap two-aggregate query) and rebuilt from the ledger on
/// mismatch — so a sale's COGS is always computed from lots that reflect
/// every synced movement, including rows pulled from other devices since
/// the last local write (see [rebuildStockLots]).
Future<int> consumeStockLots(
  AppDatabase db, {
  required String productId,
  required int qty,
  required int fallbackUnitCost,
}) async {
  if (qty <= 0) return 0;

  await _ensureLotsMatchLedger(db, productId);

  return _consumeOnly(db,
      productId: productId, qty: qty, fallbackUnitCost: fallbackUnitCost);
}

/// Heuristic consistency probe: Σ(lot remaining) vs Σ(movement qtyDelta).
/// The live write paths keep both in step locally, and foreign movements
/// pulled via sync land in the ledger only — so any gap means stale lots
/// and triggers a replay.
///
/// Not a perfect invariant: past OVERSELLS (selling more than was tracked,
/// possible at checkout — `consumeStockLots` prices the shortfall via
/// fallback instead of going negative) permanently separate the two sums by
/// the untracked units, so such products re-replay on every consume. That
/// is deliberate — the replay is idempotent, self-correcting, and bounded
/// by one product's movement history; trading a redundant replay for never
/// selling at a silently-wrong COGS is the right side of that trade-off.
Future<void> _ensureLotsMatchLedger(
    AppDatabase db, String productId) async {
  final ledgerNet = await _ledgerNet(db, productId);
  final lotsSum = await _lotsSum(db, productId);
  if (ledgerNet == lotsSum) return;
  await rebuildStockLots(db, productId);
}

Future<int> _ledgerNet(AppDatabase db, String productId) async {
  final sum = await (db.selectOnly(db.stockMovements)
        ..addColumns([db.stockMovements.qtyDelta.sum()])
        ..where(db.stockMovements.productId.equals(productId) &
            db.stockMovements.isDeleted.equals(false)))
      .getSingle();
  return sum.read(db.stockMovements.qtyDelta.sum()) ?? 0;
}

Future<int> _lotsSum(AppDatabase db, String productId) async {
  final sum = await (db.selectOnly(db.stockLots)
        ..addColumns([db.stockLots.remainingQty.sum()])
        ..where(db.stockLots.productId.equals(productId)))
      .getSingle();
  return sum.read(db.stockLots.remainingQty.sum()) ?? 0;
}

Future<int> _consumeOnly(
  AppDatabase db, {
  required String productId,
  required int qty,
  int? fallbackUnitCost,
}) async {
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

  if (fallbackUnitCost == null) return result.totalCost;
  return result.totalCost + result.shortfall * fallbackUnitCost;
}
