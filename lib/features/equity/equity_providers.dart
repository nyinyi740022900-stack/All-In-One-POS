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
/// computed over a wide-open all-time range (no new Analytics code; reuses
/// `AnalyticsRepository.summary()` unmodified). `DateTime(2020, 1, 1)`
/// matches the same "all time" floor already used elsewhere (e.g. the
/// Expense date picker's `firstDate`).
final cumulativeNetProfitProvider = FutureProvider<int>((ref) async {
  ref.watch(salesStreamProvider);
  final now = DateTime.now();
  final summary = await ref
      .watch(analyticsRepositoryProvider)
      .summary(DateTime(2020, 1, 1), now.add(const Duration(days: 1)));
  return summary.netProfit;
});

final equitySummaryProvider = FutureProvider<EquitySummary>((ref) async {
  final entries = ref.watch(equityEntriesProvider).valueOrNull ?? const [];
  final cumulativeNetProfit = await ref.watch(cumulativeNetProfitProvider.future);
  return computeEquitySummary(
      entries: entries, cumulativeNetProfit: cumulativeNetProfit);
});
