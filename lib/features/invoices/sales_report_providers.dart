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

/// Free-text product-name filter — same "type a fragment of the name"
/// convention as Stock Movements' `movementProductSearchProvider`, rather
/// than picking an exact product from a (potentially very long) list. Empty
/// means no product filter.
final salesReportProductFilterProvider = StateProvider<String>((ref) => '');

/// All sale line items, shop-wide — see `SalesRepository.watchAllSaleItems`.
final salesReportItemsProvider = StreamProvider((ref) {
  return ref.watch(salesRepositoryProvider).watchAllSaleItems();
});

/// The report for the currently-selected date range and (optional) product
/// filter.
final salesReportProvider = Provider<SalesReport>((ref) {
  final all = ref.watch(salesStreamProvider).valueOrNull ?? const [];
  final start = ref.watch(salesReportStartDateProvider);
  final end = ref.watch(salesReportEndDateProvider);
  final productQuery = ref.watch(salesReportProductFilterProvider).trim();

  Set<String>? matchingSaleIds;
  if (productQuery.isNotEmpty) {
    final items = ref.watch(salesReportItemsProvider).valueOrNull ?? const [];
    final q = productQuery.toLowerCase();
    matchingSaleIds = {
      for (final i in items)
        if (i.nameSnapshot.toLowerCase().contains(q)) i.saleId,
    };
  }

  final filtered = all.where((s) {
    if (start != null && s.finalizedAt.isBefore(start)) return false;
    if (end != null && !s.finalizedAt.isBefore(end)) return false;
    if (matchingSaleIds != null && !matchingSaleIds.contains(s.id)) {
      return false;
    }
    return true;
  }).toList();
  return buildSalesReport(filtered);
});
