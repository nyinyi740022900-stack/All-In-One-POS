import 'package:drift/drift.dart';

import '../../features/analytics/analytics_calculator.dart';
import '../local/database.dart';

/// Reads local sales/inventory and produces an [AnalyticsSummary] for a range.
/// All computation is offline — no backend needed.
class AnalyticsRepository {
  AnalyticsRepository(this._db, this._shopId);

  final AppDatabase _db;
  final String _shopId;

  /// Summary over [start, end) (end exclusive).
  ///
  /// [creditOwedBySaleId] — optional FIFO repayment allocation (see
  /// CreditRepository.owedBySale). When given, in-range credit sales that
  /// have been repaid stop counting as outstanding and their money counts
  /// as collected, matching what the Credit book shows.
  Future<AnalyticsSummary> summary(DateTime start, DateTime end,
      {Map<String, int> creditOwedBySaleId = const {}}) async {
    final sales = await (_db.select(_db.sales)
          ..where((s) =>
              s.shopId.equals(_shopId) &
              s.isDeleted.equals(false) &
              s.finalizedAt.isBiggerOrEqualValue(start) &
              s.finalizedAt.isSmallerThanValue(end)))
        .get();

    final saleRows = sales
        .map((s) => (
              id: s.id,
              total: s.total,
              paid: s.paid,
              paymentMethod: s.paymentMethod,
              discount: s.discount,
              finalizedAt: s.finalizedAt,
              isRefund: s.refundOfSaleId != null,
              staffId: s.staffId,
            ))
        .toList();

    final saleIds = sales.map((s) => s.id).toList();
    final items = saleIds.isEmpty
        ? <SaleItem>[]
        : await (_db.select(_db.saleItems)
              ..where((i) => i.saleId.isIn(saleIds)))
            .get();
    final itemRows = items
        .map((i) => (
              productId: i.productId,
              name: i.nameSnapshot,
              qty: i.qty,
              lineTotal: i.lineTotal,
              costSnapshot: i.costSnapshot,
            ))
        .toList();

    final products = await (_db.select(_db.products)
          ..where((p) => p.shopId.equals(_shopId)))
        .get();
    final productCost = {for (final p in products) p.id: p.costPrice};

    final levels = await (_db.select(_db.stockLevels)
          ..where((s) => s.shopId.equals(_shopId) & s.isDeleted.equals(false)))
        .get();
    var stockValue = 0;
    for (final lvl in levels) {
      stockValue += lvl.quantity * (productCost[lvl.productId] ?? 0);
    }

    final expenseRows = await (_db.select(_db.expenses)
          ..where((e) =>
              e.shopId.equals(_shopId) &
              e.isDeleted.equals(false) &
              e.date.isBiggerOrEqualValue(start) &
              e.date.isSmallerThanValue(end)))
        .get();
    final expenses = expenseRows.fold<int>(0, (sum, e) => sum + e.amount);

    return computeAnalytics(
      sales: saleRows,
      items: itemRows,
      productCost: productCost,
      stockValue: stockValue,
      start: start,
      end: end,
      expenses: expenses,
      creditOwedBySaleId: creditOwedBySaleId,
    );
  }

  /// Net profit over [start, end) as ONE SQL statement of three scalar
  /// aggregates — Σ sale totals − Σ item cost − Σ expenses — without ever
  /// materialising rows into Dart.
  ///
  /// Why not reuse [summary]: Owner's Equity folds net profit since
  /// INCEPTION on every sale / expense / cost-price write. `summary` loads
  /// every sale + item + product AND stock level in range and folds them in
  /// Dart — O(business history) allocations on the UI isolate that grow
  /// every year the shop trades (audit C2). These three SUMs run inside
  /// SQLite and allocate one result row.
  ///
  /// Parity with `summary(...).netProfit` is exact (and pinned by tests):
  /// revenue = Σ sales.total; cost = Σ COALESCE(item.cost_snapshot,
  /// qty × current product cost, 0) — tombstoned products still count,
  /// foreign-shop product ids contribute 0 (the shop filter sits in the
  /// JOIN, mirroring summary's per-shop product map); refunds are ordinary
  /// negated rows; expenses share the same shop/is_deleted/date window.
  Future<int> cumulativeNetProfit({
    required DateTime start,
    required DateTime end,
  }) async {
    final row = await _db.customSelect(
      '''
      SELECT
        (SELECT COALESCE(SUM(s.total), 0) FROM sales AS s
          WHERE s.shop_id = ?1 AND s.is_deleted = 0
            AND s.finalized_at >= ?2 AND s.finalized_at < ?3)
        -
        (SELECT COALESCE(SUM(COALESCE(si.cost_snapshot,
              si.qty * COALESCE(p.cost_price, 0))), 0)
          FROM sale_items AS si
          JOIN sales AS s ON s.id = si.sale_id
          LEFT JOIN products AS p
            ON p.id = si.product_id AND p.shop_id = ?1
          WHERE s.shop_id = ?1 AND s.is_deleted = 0
            AND s.finalized_at >= ?2 AND s.finalized_at < ?3)
        -
        (SELECT COALESCE(SUM(e.amount), 0) FROM expenses AS e
          WHERE e.shop_id = ?1 AND e.is_deleted = 0
            AND e.date >= ?2 AND e.date < ?3)
        AS net_profit
      ''',
      variables: [
        Variable.withString(_shopId),
        Variable.withDateTime(start),
        Variable.withDateTime(end),
      ],
    ).getSingle();
    return row.read<int>('net_profit');
  }

  /// Same shop-scoped/date-ranged expense query [summary] runs for its
  /// lump-sum `expenses`, grouped by category instead — for a P&L
  /// statement's per-line breakdown (rent/utilities/wages/transport/
  /// packaging/other). Only categories with activity in range appear.
  Future<Map<String, int>> expensesByCategory(
      DateTime start, DateTime end) async {
    final expenseRows = await (_db.select(_db.expenses)
          ..where((e) =>
              e.shopId.equals(_shopId) &
              e.isDeleted.equals(false) &
              e.date.isBiggerOrEqualValue(start) &
              e.date.isSmallerThanValue(end)))
        .get();
    final byCategory = <String, int>{};
    for (final e in expenseRows) {
      byCategory[e.category] = (byCategory[e.category] ?? 0) + e.amount;
    }
    return byCategory;
  }
}
