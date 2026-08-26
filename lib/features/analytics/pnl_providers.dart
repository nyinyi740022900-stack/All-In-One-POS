import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../credit/credit_providers.dart';
import '../sell/sales_providers.dart';
import 'analytics_providers.dart';
import 'pnl_data.dart';

/// Inclusive lower / exclusive upper bound for the P&L's date range — null
/// means "use the default" (the current month), same two-provider shape
/// Sales Report's own date filter uses.
final pnlStartDateProvider = StateProvider<DateTime?>((ref) => null);
final pnlEndDateProvider = StateProvider<DateTime?>((ref) => null);

final pnlStatementProvider = FutureProvider<PnlStatement>((ref) async {
  // Consolidated invalidation signals (audit M4): sales, the shared expense
  // signal, the memoized product-cost map, the memoized stock value, and
  // sale items — `summary()` JOINs sale_items for per-line COGS, so a sync
  // pull where items arrive after their parent sale must trigger a recompute
  // or the COGS stays 0 until the next unrelated write.
  ref.watch(salesStreamProvider);
  ref.watch(expenseChangesProvider);
  ref.watch(productCostMapProvider);
  ref.watch(stockValueProvider);
  ref.watch(saleItemChangesProvider);
  final now = DateTime.now();
  final defaultStart = DateTime(now.year, now.month, 1);
  final defaultEnd =
      DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  final start = ref.watch(pnlStartDateProvider) ?? defaultStart;
  final end = ref.watch(pnlEndDateProvider) ?? defaultEnd;
  // Repayment-aware credit figures (same FIFO map the Credit book uses).
  ref.watch(creditOwedBySaleProvider);
  final repo = ref.watch(analyticsRepositoryProvider);
  final summary = await repo.summary(start, end,
      creditOwedBySaleId: ref.watch(creditOwedBySaleProvider));
  final byCategory = await repo.expensesByCategory(start, end);
  return buildPnlStatement(summary,
      expensesByCategory: byCategory, start: start, end: end);
});
