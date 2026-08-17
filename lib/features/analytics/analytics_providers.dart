import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/database.dart';
import '../../data/repositories/analytics_repository.dart';
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

/// Just enough to trigger `analyticsSummaryProvider` to recompute when an
/// expense is added/edited/deleted — the actual figures are read fresh from
/// the repository, not from this stream's rows.
final _expenseChangesProvider = StreamProvider<List<Expense>>((ref) {
  final db = ref.watch(databaseProvider);
  final shopId = ref.watch(shopIdProvider);
  return (db.select(db.expenses)
        ..where((e) => e.shopId.equals(shopId) & e.isDeleted.equals(false)))
      .watch();
});

/// Same watch-only shape as [_expenseChangesProvider] — `summary()` also
/// reads every product's `costPrice` (for stock value / COGS), which can
/// change with no sale involved (editing a product's cost). Without this,
/// Analytics/P&L/Owner's Equity all silently kept showing stale figures
/// after a cost-price edit.
final _productChangesProvider = StreamProvider<List<Product>>((ref) {
  final db = ref.watch(databaseProvider);
  final shopId = ref.watch(shopIdProvider);
  return (db.select(db.products)..where((p) => p.shopId.equals(shopId)))
      .watch();
});

/// Same reasoning as [_productChangesProvider] — `summary()` reads
/// `stockLevels` for stock value, which changes on a plain stock adjustment
/// with no sale either.
final _stockLevelChangesProvider = StreamProvider<List<StockLevel>>((ref) {
  final db = ref.watch(databaseProvider);
  final shopId = ref.watch(shopIdProvider);
  return (db.select(db.stockLevels)
        ..where((s) => s.shopId.equals(shopId) & s.isDeleted.equals(false)))
      .watch();
});

final analyticsSummaryProvider = FutureProvider<AnalyticsSummary>((ref) async {
  // Recompute whenever sales, expenses, product cost, or stock levels
  // change so the dashboard (and everything downstream that reuses this —
  // P&L, Owner's Equity) stays live.
  ref.watch(salesStreamProvider);
  ref.watch(_expenseChangesProvider);
  ref.watch(_productChangesProvider);
  ref.watch(_stockLevelChangesProvider);
  final range = ref.watch(analyticsRangeProvider);
  final bounds = rangeBounds(range, DateTime.now());
  return ref
      .watch(analyticsRepositoryProvider)
      .summary(bounds.start, bounds.end);
});
