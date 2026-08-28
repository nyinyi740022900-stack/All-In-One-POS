import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/database.dart';
import '../../data/repositories/analytics_repository.dart';
import '../credit/credit_providers.dart';
import '../sell/sales_providers.dart';
import 'analytics_calculator.dart';

enum AnalyticsRange { today, week, month }

final analyticsRangeProvider =
    StateProvider<AnalyticsRange>((ref) => AnalyticsRange.week);

final analyticsRepositoryProvider = Provider<AnalyticsRepository>((ref) {
  return AnalyticsRepository(
      ref.watch(databaseProvider), ref.watch(shopIdProvider));
});

/// (start, end-exclusive) bounds for a range, aligned to day boundaries.
({DateTime start, DateTime end}) rangeBounds(AnalyticsRange r, DateTime now) {
  final todayStart = DateTime(now.year, now.month, now.day);
  final tomorrow = todayStart.add(const Duration(days: 1));
  return switch (r) {
    AnalyticsRange.today => (start: todayStart, end: tomorrow),
    AnalyticsRange.week => (
        start: todayStart.subtract(const Duration(days: 6)),
        end: tomorrow
      ),
    AnalyticsRange.month => (
        start: todayStart.subtract(const Duration(days: 29)),
        end: tomorrow
      ),
  };
}

/// Just enough to trigger summary recomputes when an expense is
/// added/edited/deleted — the actual figures are read fresh from the
/// repository, not from this stream's rows. Public so P&L and Owner's
/// Equity reuse ONE signal instead of each keeping a private duplicate of
/// the same watch (audit M4 consolidation).
final expenseChangesProvider = StreamProvider<List<Expense>>((ref) {
  final db = ref.watch(databaseProvider);
  final shopId = ref.watch(shopIdProvider);
  return (db.select(db.expenses)
        ..where((e) => e.shopId.equals(shopId) & e.isDeleted.equals(false)))
      .watch();
});

/// Feed for [productCostMapProvider] — kept library-private; consumers must
/// watch the memoized map, not this raw stream.
final _productChangesProvider = StreamProvider<List<Product>>((ref) {
  final db = ref.watch(databaseProvider);
  final shopId = ref.watch(shopIdProvider);
  return (db.select(db.products)..where((p) => p.shopId.equals(shopId)))
      .watch();
});

/// `{productId: costPrice}` for the active shop — the ONLY product-derived
/// input the summaries actually need (COGS fallback + stock value).
///
/// Content-memoized on purpose (audit M4): renaming a product or changing
/// its photo fires the products stream just like a cost edit does, but the
/// map contents are equal, so the SAME instance is returned and downstream
/// Analytics/P&L/Equity recomputes are suppressed. Without this, every
/// rename re-ran three expensive summaries for an identical result.
Map<String, int>? _costMapCache;
final productCostMapProvider = Provider<Map<String, int>>((ref) {
  final products =
      ref.watch(_productChangesProvider).valueOrNull ?? const <Product>[];
  final map = {for (final p in products) p.id: p.costPrice};
  final cached = _costMapCache;
  if (cached != null && _mapsEqual(cached, map)) return cached;
  return _costMapCache = map;
});

bool _mapsEqual(Map<String, int> a, Map<String, int> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}

/// Feed for [stockValueProvider].
final _stockLevelChangesProvider = StreamProvider<List<StockLevel>>((ref) {
  final db = ref.watch(databaseProvider);
  final shopId = ref.watch(shopIdProvider);
  return (db.select(db.stockLevels)
        ..where((s) => s.shopId.equals(shopId) & s.isDeleted.equals(false)))
      .watch();
});

final _stockLotChangesProvider = StreamProvider<List<StockLot>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.stockLots).watch();
});

final _liveProductIdsProvider = Provider<Set<String>>((ref) {
  final products =
      ref.watch(_productChangesProvider).valueOrNull ?? const <Product>[];
  return {for (final p in products) if (!p.isDeleted) p.id};
});

/// Σ FIFO lots (`remainingQty × unitCost`) for live products; qty ×
/// current cost only when a product has no lots. Deleted products are
/// excluded so tombstoned catalogue rows cannot inflate inventory value.
int? _stockValueCache;
final stockValueProvider = Provider<int>((ref) {
  final levels =
      ref.watch(_stockLevelChangesProvider).valueOrNull ?? const <StockLevel>[];
  final lots =
      ref.watch(_stockLotChangesProvider).valueOrNull ?? const <StockLot>[];
  final costs = ref.watch(productCostMapProvider);
  final liveIds = ref.watch(_liveProductIdsProvider);
  final lotValueByProduct = <String, int>{};
  for (final lot in lots) {
    if (!liveIds.contains(lot.productId)) continue;
    lotValueByProduct[lot.productId] =
        (lotValueByProduct[lot.productId] ?? 0) +
            lot.remainingQty * lot.unitCost;
  }
  var value = 0;
  for (final l in levels) {
    if (!liveIds.contains(l.productId)) continue;
    final fromLots = lotValueByProduct[l.productId];
    if (fromLots != null) {
      value += fromLots;
    } else {
      value += l.quantity * (costs[l.productId] ?? 0);
    }
  }
  final cached = _stockValueCache;
  if (cached != null && cached == value) return cached;
  return _stockValueCache = value;
});

/// Same watch-only shape as the invalidation-only providers above —
/// `summary()` reads `sale_items.costSnapshot` for exact per-line COGS, and
/// sale_items rows can arrive AFTER their parent sale during a sync pull
/// (the engine inserts into `sales` first, then `sale_items`), so watching
/// only the sales table misses the moment profit actually becomes correct.
/// Public so equity/accounting providers that fold the same SQL/Dart
/// COGS (see [cumulativeNetProfitProvider], [pnlStatementProvider]) can
/// share ONE signal instead of each keeping a private duplicate (audit
/// M4 — the same stale-watch bug that left net-profit inflated until any
/// other write fired during a sync pull).
final saleItemChangesProvider = StreamProvider<List<SaleItem>>((ref) {
  final db = ref.watch(databaseProvider);
  final shopId = ref.watch(shopIdProvider);
  return (db.select(db.saleItems)
          ..where((i) => i.shopId.equals(shopId)))
      .watch();
});

final analyticsSummaryProvider = FutureProvider<AnalyticsSummary>((ref) async {
  // Recompute whenever sales, sale items (COGS snapshots), expenses,
  // product cost, or stock levels change so the dashboard (and everything
  // downstream that reuses this — P&L, Owner's Equity) stays live.
  ref.watch(salesStreamProvider);
  // Repayment allocation (Credit book's FIFO map) feeds creditOutstanding /
  // collected — watching it keeps those figures live when a repayment is
  // recorded (this exact mismatch shipped before: Credit book showed 0
  // while Analytics kept counting a fully-repaid sale as outstanding).
  ref.watch(creditOwedBySaleProvider);
  ref.watch(saleItemChangesProvider);
  ref.watch(expenseChangesProvider);
  // Narrowed signals (audit M4): the memoized cost map + stock value
  // instead of raw products/stock_levels streams, so renames and photo
  // changes no longer re-run the whole summary.
  ref.watch(productCostMapProvider);
  ref.watch(stockValueProvider);
  final range = ref.watch(analyticsRangeProvider);
  final bounds = rangeBounds(range, DateTime.now());
  return ref
      .watch(analyticsRepositoryProvider)
      .summary(bounds.start, bounds.end,
          creditOwedBySaleId:
              ref.watch(creditOwedBySaleProvider));
});
