import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/database.dart';
import '../analytics/analytics_providers.dart';
import '../sell/sales_providers.dart';
import 'equity_calculator.dart';
import 'equity_repository.dart';

final equityRepositoryProvider = Provider<EquityRepository>((ref) {
  return EquityRepository(
    ref.watch(databaseProvider),
    ref.watch(shopIdProvider),
  );
});

final equityEntriesProvider = StreamProvider<List<EquityEntry>>((ref) {
  return ref.watch(equityRepositoryProvider).watchEntries();
});

/// Cumulative Net Profit since inception — the P&L's own `netProfit`,
/// computed over a wide-open all-time range as THREE SQL aggregates in one
/// statement (`AnalyticsRepository.cumulativeNetProfit`): Σ sale totals −
/// Σ item cost − Σ expenses. It never materialises rows into Dart (audit
/// C2: this used to reuse `summary()`, loading every sale, item, product
/// AND stock level ever recorded on every recompute — O(business history)
/// on the UI isolate, growing every year the shop trades).
///
/// `DateTime(2020, 1, 1)` matches the same "all time" floor already used
/// elsewhere (e.g. the Expense date picker's `firstDate`).
///
/// Triggers are the consolidated narrowed signals (audit M4): sales, the
/// shared expense signal, and the memoized product-cost map — each
/// recompute is now three indexed SUMs, not a full history load. The FIFO
/// credit map is deliberately NOT watched: it only affects
/// `creditOutstanding`/`collected`, never `netProfit`, so a repayment no
/// longer re-runs this aggregation for an identical result. Stock levels
/// are not watched either — `netProfit` never reads `stockValue`.
final cumulativeNetProfitProvider = FutureProvider<int>((ref) async {
  ref.watch(salesStreamProvider);
  ref.watch(expenseChangesProvider);
  ref.watch(productCostMapProvider);
  // The SQL query JOINs sale_items for COGS (cost_snapshot / qty × cost_price),
  // so a sale_item write — especially a sync pull where items arrive after
  // their parent sale — must recompute. Without this, net profit stayed
  // inflated (COGS = 0) until any other watched table fired (audit M4).
  ref.watch(saleItemChangesProvider);
  final end = DateTime.now().add(const Duration(days: 1));
  return ref.watch(analyticsRepositoryProvider).cumulativeNetProfit(
        start: DateTime(2020, 1, 1),
        end: end,
      );
});

final equitySummaryProvider = FutureProvider<EquitySummary>((ref) async {
  final entries = ref.watch(equityEntriesProvider).valueOrNull ?? const [];
  final cumulativeNetProfit = await ref.watch(cumulativeNetProfitProvider.future);
  return computeEquitySummary(
      entries: entries, cumulativeNetProfit: cumulativeNetProfit);
});
