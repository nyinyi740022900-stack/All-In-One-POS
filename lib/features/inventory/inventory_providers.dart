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

/// Products filtered by the current search query (name / sku / barcode) and
/// the selected category.
final filteredProductsProvider = Provider<List<ProductWithStock>>((ref) {
  final all = ref.watch(productsStreamProvider).valueOrNull ?? const [];
  final q = ref.watch(inventorySearchProvider).trim().toLowerCase();
  final categoryId = ref.watch(inventoryCategoryProvider);

  return all.where((p) {
    final prod = p.product;
    if (categoryId != null && prod.categoryId != categoryId) return false;
    if (q.isEmpty) return true;
    return prod.name.toLowerCase().contains(q) ||
        (prod.sku?.toLowerCase().contains(q) ?? false) ||
        (prod.barcode?.toLowerCase().contains(q) ?? false);
  }).toList();
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
