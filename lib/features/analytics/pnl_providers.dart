import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/database.dart';
import '../sell/sales_providers.dart';
import 'analytics_providers.dart';
import 'pnl_data.dart';

/// Inclusive lower / exclusive upper bound for the P&L's date range — null
/// means "use the default" (the current month), same two-provider shape
/// Sales Report's own date filter uses.
final pnlStartDateProvider = StateProvider<DateTime?>((ref) => null);
final pnlEndDateProvider = StateProvider<DateTime?>((ref) => null);

/// Just enough to trigger a recompute when an expense changes — same
/// pattern `analytics_providers.dart`'s own `_expenseChangesProvider` uses.
final _pnlExpenseChangesProvider = StreamProvider<List<Expense>>((ref) {
  final db = ref.watch(databaseProvider);
  final shopId = ref.watch(shopIdProvider);
  return (db.select(db.expenses)
        ..where((e) => e.shopId.equals(shopId) & e.isDeleted.equals(false)))
      .watch();
});

/// `repo.summary()` below also reads product cost + stock levels for COGS —
/// same reasoning and shape as `analytics_providers.dart`'s own
/// `_productChangesProvider`/`_stockLevelChangesProvider` (this file can't
/// reuse those directly, they're library-private there).
final _pnlProductChangesProvider = StreamProvider<List<Product>>((ref) {
  final db = ref.watch(databaseProvider);
  final shopId = ref.watch(shopIdProvider);
  return (db.select(db.products)..where((p) => p.shopId.equals(shopId)))
      .watch();
});

final _pnlStockLevelChangesProvider = StreamProvider<List<StockLevel>>((ref) {
  final db = ref.watch(databaseProvider);
  final shopId = ref.watch(shopIdProvider);
  return (db.select(db.stockLevels)
        ..where((s) => s.shopId.equals(shopId) & s.isDeleted.equals(false)))
      .watch();
});

final pnlStatementProvider = FutureProvider<PnlStatement>((ref) async {
  ref.watch(salesStreamProvider);
  ref.watch(_pnlExpenseChangesProvider);
  ref.watch(_pnlProductChangesProvider);
  ref.watch(_pnlStockLevelChangesProvider);
  final now = DateTime.now();
  final defaultStart = DateTime(now.year, now.month, 1);
  final defaultEnd =
      DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  final start = ref.watch(pnlStartDateProvider) ?? defaultStart;
  final end = ref.watch(pnlEndDateProvider) ?? defaultEnd;
  final repo = ref.watch(analyticsRepositoryProvider);
  final summary = await repo.summary(start, end);
  final byCategory = await repo.expensesByCategory(start, end);
  return buildPnlStatement(summary,
      expensesByCategory: byCategory, start: start, end: end);
});
