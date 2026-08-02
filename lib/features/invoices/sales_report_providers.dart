import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sell/sales_providers.dart';
import 'sales_report_data.dart';

/// Inclusive lower bound for the sales report's date filter — null means no
/// lower bound (all time). Two separate `DateTime?` providers (inclusive
/// start, exclusive end), same pattern as Inventory's stock-history date
/// filter, so this file stays UI-framework-free.
final salesReportStartDateProvider = StateProvider<DateTime?>((ref) => null);

/// Exclusive upper bound (the day *after* the inclusive end day the owner
/// picked) — null means no upper bound.
final salesReportEndDateProvider = StateProvider<DateTime?>((ref) => null);

/// The report for the currently-selected date range.
final salesReportProvider = Provider<SalesReport>((ref) {
  final all = ref.watch(salesStreamProvider).valueOrNull ?? const [];
  final start = ref.watch(salesReportStartDateProvider);
  final end = ref.watch(salesReportEndDateProvider);
  final filtered = all.where((s) {
    if (start != null && s.finalizedAt.isBefore(start)) return false;
    if (end != null && !s.finalizedAt.isBefore(end)) return false;
    return true;
  }).toList();
  return buildSalesReport(filtered);
});
