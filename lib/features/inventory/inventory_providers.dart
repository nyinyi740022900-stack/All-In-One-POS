import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/search_debounce.dart';
import '../../data/local/database.dart';
import '../../data/repositories/inventory_repository.dart';
import '../../domain/product_with_stock.dart';
import '../printing/printing_providers.dart' show trackStockProvider;
final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final shopId = ref.watch(shopIdProvider);
  return InventoryRepository(db, shopId);
});

/// Search query for the inventory list.
final inventorySearchProvider = StateProvider<String>((ref) => '');

/// The query the EXPENSIVE listeners (list filter, category counts) consume
/// — settles [kSearchDebounce] after typing pauses so a burst of keystrokes
/// refilters the catalogue once, not once per character (audit H1). The
/// text field itself and the "no results" label keep watching
/// [inventorySearchProvider] for same-keystroke response.
final debouncedInventorySearchProvider =
    debouncedSearchProvider(inventorySearchProvider);

final productsStreamProvider =
    StreamProvider<List<ProductWithStock>>((ref) {
  return ref.watch(inventoryRepositoryProvider).watchProducts();
});

/// Selected category filter for the inventory list (null = all categories).
final inventoryCategoryProvider = StateProvider<String?>((ref) => null);

/// When true, the inventory list shows only products that need a stock
/// glance: at or below their reorder level, or fully out. Toggled by the
/// low-stock chip / the tappable low-stock banner.
final inventoryLowStockOnlyProvider = StateProvider<bool>((ref) => false);

/// A product that needs attention: out of stock, OR at/below its reorder
/// level. `isLowStock` alone misses a product that ran out with no reorder
/// level ever set — arguably the loudest case of all.
bool needsStockAttention(ProductWithStock p) =>
    p.quantity <= 0 || p.isLowStock;

/// Shared by [filteredProductsProvider] and [inventoryCategoryCountsProvider]
/// so a chip's count can never disagree with the list it describes.
bool _matchesInventoryQuery(Product prod, String q) {
  if (q.isEmpty) return true;
  return prod.name.toLowerCase().contains(q) ||
      (prod.sku?.toLowerCase().contains(q) ?? false) ||
      (prod.barcode?.toLowerCase().contains(q) ?? false);
}

/// Products filtered by the current search query (name / sku / barcode), the
/// selected category, and the low-stock-only toggle.
///
/// The toggle is ignored when the shop doesn't track stock — the chip is
/// hidden then, and a filter that can no longer be seen must not keep
/// silently hiding rows.
final filteredProductsProvider = Provider<List<ProductWithStock>>((ref) {
  final all = ref.watch(productsStreamProvider).valueOrNull ?? const [];
  final q =
      ref.watch(debouncedInventorySearchProvider).trim().toLowerCase();
  final categoryId = ref.watch(inventoryCategoryProvider);
  final lowOnly = ref.watch(inventoryLowStockOnlyProvider);
  final trackStock = ref.watch(trackStockProvider).valueOrNull ?? true;

  return all.where((p) {
    if (categoryId != null && p.product.categoryId != categoryId) return false;
    if (lowOnly && trackStock && !needsStockAttention(p)) return false;
    return _matchesInventoryQuery(p.product, q);
  }).toList();
});

/// How many products each category chip would show if tapped, keyed by
/// category id — `null` holds the "All" total. Counted against the *current
/// search* (not the whole catalogue) so a chip never promises rows the list
/// won't show. Mirrors `sellCategoryCountsProvider`; both feed the shared
/// `CategoryFilterBar`.
final inventoryCategoryCountsProvider = Provider<Map<String?, int>>((ref) {
  final all = ref.watch(productsStreamProvider).valueOrNull ?? const [];
  final q =
      ref.watch(debouncedInventorySearchProvider).trim().toLowerCase();
  final counts = <String?, int>{};
  var total = 0;
  for (final p in all) {
    if (!_matchesInventoryQuery(p.product, q)) continue;
    total++;
    final id = p.product.categoryId;
    if (id != null) counts[id] = (counts[id] ?? 0) + 1;
  }
  counts[null] = total;
  return counts;
});

final lowStockCountProvider = Provider<int>((ref) {
  final all = ref.watch(productsStreamProvider).valueOrNull ?? const [];
  // Same predicate the low-stock filter itself applies — counting only
  // isLowStock (which requires a reorder level) used to report 0 for a
  // product that sold out with no reorder level ever set, silencing every
  // signal (chip, banner, Analytics glance) while the filter, tile badge,
  // and this doc comment all agreed it needs attention.
  return all.where(needsStockAttention).length;
});

/// Live quantity per product id, rebuilt ONLY when the products×stock stream
/// emits (audit M3). Cart UIs used to build this exact map inside their own
/// `build` — watching the cart too — so every qty tap / keypad digit
/// re-scanned the whole catalogue just to look up two or three ids. Reading
/// `ref.watch(stockByIdProvider)[id]` from the sheet costs O(1) per rebuild.
final stockByIdProvider = Provider<Map<String, int>>((ref) {
  final all = ref.watch(productsStreamProvider).valueOrNull ?? const [];
  return {for (final p in all) p.product.id: p.quantity};
});

final categoriesStreamProvider = StreamProvider<List<Category>>((ref) {
  return ref.watch(inventoryRepositoryProvider).watchCategories();
});

final stockMovementsProvider =
    StreamProvider.family<List<StockMovement>, String>((ref, productId) {
  return ref.watch(inventoryRepositoryProvider).watchStockMovements(productId);
});

// --- Shop-wide "Stock history" screen (Inventory tab) -----------------------

/// Inclusive lower bound for the shop-wide stock history filter — null means
/// no lower bound (all time).
final movementStartDateProvider = StateProvider<DateTime?>((ref) => null);

/// Exclusive upper bound (the day *after* the inclusive end day the owner
/// picked) — null means no upper bound.
final movementEndDateProvider = StateProvider<DateTime?>((ref) => null);

/// Which movement types to show — defaults to restocks + adjustments only,
/// since sales/returns are already visible via Invoices.
final movementTypeFilterProvider =
    StateProvider<Set<String>>((ref) => {'purchase', 'adjustment'});

/// Product-name fragment typed into the stock-history screen's product
/// filter (case-insensitive contains). Empty = every product.
final movementProductSearchProvider = StateProvider<String>((ref) => '');

/// Debounced mirror of [movementProductSearchProvider] — the movement list
/// can span years, so refiltering per keystroke repeats the H1 problem this
/// debounce helper exists for.
final debouncedMovementProductSearchProvider =
    debouncedSearchProvider(movementProductSearchProvider);

final allMovementsProvider = StreamProvider<List<StockMovement>>((ref) {
  final start = ref.watch(movementStartDateProvider);
  final end = ref.watch(movementEndDateProvider);
  return ref
      .watch(inventoryRepositoryProvider)
      .watchAllMovements(start: start, end: end);
});

/// A movement paired with its product's name, for a list that spans every
/// product (StockMovements itself only carries the product id).
class MovementWithProduct {
  const MovementWithProduct(
      {required this.movement, required this.productName});
  final StockMovement movement;
  final String productName;
}

final filteredMovementsProvider = Provider<List<MovementWithProduct>>((ref) {
  final movements = ref.watch(allMovementsProvider).valueOrNull ?? const [];
  final types = ref.watch(movementTypeFilterProvider);
  final productQuery = ref
      .watch(debouncedMovementProductSearchProvider)
      .trim()
      .toLowerCase();
  final products = ref.watch(productsStreamProvider).valueOrNull ?? const [];
  final nameById = {for (final p in products) p.product.id: p.product.name};
  return movements
      .where((m) => types.isEmpty || types.contains(m.type))
      .where((m) =>
          productQuery.isEmpty ||
          (nameById[m.productId] ?? '').toLowerCase().contains(productQuery))
      .map((m) => MovementWithProduct(
            movement: m,
            productName: nameById[m.productId] ?? m.productId,
          ))
      .toList();
});
