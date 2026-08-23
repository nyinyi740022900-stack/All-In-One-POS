import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/search_debounce.dart';
import '../../data/local/database.dart';
import '../../data/repositories/sales_repository.dart';
import '../../domain/product_with_stock.dart';
import '../inventory/inventory_providers.dart';

final salesRepositoryProvider = Provider<SalesRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final shopId = ref.watch(shopIdProvider);
  return SalesRepository(db, shopId);
});

final salesStreamProvider = StreamProvider<List<Sale>>((ref) {
  return ref.watch(salesRepositoryProvider).watchSales();
});

typedef SaleDetail = ({Sale sale, List<SaleItem> items});

final saleDetailProvider =
    FutureProvider.family<SaleDetail, String>((ref, saleId) async {
  final repo = ref.watch(salesRepositoryProvider);
  final sale = await repo.getSale(saleId);
  final items = await repo.saleItems(saleId);
  return (sale: sale, items: items);
});

/// The refund row for a sale, if one exists. Null if not refunded.
final refundOfProvider =
    FutureProvider.family<Sale?, String>((ref, saleId) {
  ref.watch(salesStreamProvider);
  return ref.watch(salesRepositoryProvider).refundOf(saleId);
});

/// Search + category filter for the Sell screen's product grid. Kept separate
/// from the Inventory tab's filter so the two don't interfere.
final sellSearchProvider = StateProvider<String>((ref) => '');
final sellCategoryProvider = StateProvider<String?>((ref) => null);

/// The query the EXPENSIVE listeners (grid filter, category counts) consume
/// — settles [kSearchDebounce] after typing pauses so a burst of keystrokes
/// refilters the catalogue once, not once per character (audit H1). The
/// text field itself and the empty-state label keep watching
/// [sellSearchProvider] for same-keystroke response.
final debouncedSellSearchProvider =
    debouncedSearchProvider(sellSearchProvider);

/// Shared by [sellProductsProvider] and [sellCategoryCountsProvider] so the
/// chip counts can never disagree with the grid they describe.
bool _matchesSellQuery(Product prod, String q) {
  if (q.isEmpty) return true;
  return prod.name.toLowerCase().contains(q) ||
      (prod.sku?.toLowerCase().contains(q) ?? false) ||
      (prod.barcode?.toLowerCase().contains(q) ?? false);
}

/// Products shown on the Sell grid, filtered by the current search query
/// (name / sku / barcode) and selected category.
final sellProductsProvider = Provider<List<ProductWithStock>>((ref) {
  final all = ref.watch(productsStreamProvider).valueOrNull ?? const [];
  final q = ref.watch(debouncedSellSearchProvider).trim().toLowerCase();
  final categoryId = ref.watch(sellCategoryProvider);

  return all.where((p) {
    if (categoryId != null && p.product.categoryId != categoryId) return false;
    return _matchesSellQuery(p.product, q);
  }).toList();
});

/// How many products each category chip would show if tapped, keyed by
/// category id — with `null` holding the "All" total. Counted against the
/// *current search*, not the whole catalogue, so a chip never promises rows
/// the grid won't show. Derived in a provider (rather than folded inside the
/// filter bar's `build`) so it recomputes only when products or the query
/// actually change.
final sellCategoryCountsProvider = Provider<Map<String?, int>>((ref) {
  final all = ref.watch(productsStreamProvider).valueOrNull ?? const [];
  final q = ref.watch(debouncedSellSearchProvider).trim().toLowerCase();
  final counts = <String?, int>{};
  var total = 0;
  for (final p in all) {
    if (!_matchesSellQuery(p.product, q)) continue;
    total++;
    final id = p.product.categoryId;
    if (id != null) counts[id] = (counts[id] ?? 0) + 1;
  }
  counts[null] = total;
  return counts;
});
