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
  Future<AnalyticsSummary> summary(DateTime start, DateTime end) async {
    final sales = await (_db.select(_db.sales)
          ..where((s) =>
              s.shopId.equals(_shopId) &
              s.isDeleted.equals(false) &
              s.finalizedAt.isBiggerOrEqualValue(start) &
              s.finalizedAt.isSmallerThanValue(end)))
        .get();

    final saleRows = sales
        .map((s) => (
              total: s.total,
              paid: s.paid,
              paymentMethod: s.paymentMethod,
              discount: s.discount,
              finalizedAt: s.finalizedAt,
              isRefund: s.refundOfSaleId != null,
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
    );
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
