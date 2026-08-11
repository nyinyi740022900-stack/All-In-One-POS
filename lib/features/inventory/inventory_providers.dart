import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/database.dart';
import '../../data/repositories/inventory_repository.dart';
import '../../domain/product_with_stock.dart';

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final shopId = ref.watch(shopIdProvider);
  return InventoryRepository(db, shopId);
});

/// Search query for the inventory list.
final inventorySearchProvider = StateProvider<String>((ref) => '');

final productsStreamProvider =
    StreamProvider<List<ProductWithStock>>((ref) {
  return ref.watch(inventoryRepositoryProvider).watchProducts();
});

/// Selected category filter for the inventory list (null = all categories).
final inventoryCategoryProvider = StateProvider<String?>((ref) => null);

/// Shared by [filteredProductsProvider] and [inventoryCategoryCountsProvider]
/// so a chip's count can never disagree with the list it describes.
bool _matchesInventoryQuery(Product prod, String q) {
  if (q.isEmpty) return true;
  return prod.name.toLowerCase().contains(q) ||
      (prod.sku?.toLowerCase().contains(q) ?? false) ||
      (prod.barcode?.toLowerCase().contains(q) ?? false);
}

/// Products filtered by the current search query (name / sku / barcode) and
/// the selected category.
final filteredProductsProvider = Provider<List<ProductWithStock>>((ref) {
  final all = ref.watch(productsStreamProvider).valueOrNull ?? const [];
  final q = ref.watch(inventorySearchProvider).trim().toLowerCase();
  final categoryId = ref.watch(inventoryCategoryProvider);

  return all.where((p) {
    if (categoryId != null && p.product.categoryId != categoryId) return false;
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
  final q = ref.watch(inventorySearchProvider).trim().toLowerCase();
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
  return all.where((p) => p.isLowStock).length;
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
  final products = ref.watch(productsStreamProvider).valueOrNull ?? const [];
  final nameById = {for (final p in products) p.product.id: p.product.name};
  return movements
      .where((m) => types.isEmpty || types.contains(m.type))
      .map((m) => MovementWithProduct(
            movement: m,
            productName: nameById[m.productId] ?? m.productId,
          ))
      .toList();
});
