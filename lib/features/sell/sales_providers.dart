import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
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

/// Products shown on the Sell grid, filtered by the current search query
/// (name / sku / barcode) and selected category.
final sellProductsProvider = Provider<List<ProductWithStock>>((ref) {
  final all = ref.watch(productsStreamProvider).valueOrNull ?? const [];
  final q = ref.watch(sellSearchProvider).trim().toLowerCase();
  final categoryId = ref.watch(sellCategoryProvider);

  return all.where((p) {
    final prod = p.product;
    if (categoryId != null && prod.categoryId != categoryId) return false;
    if (q.isEmpty) return true;
    return prod.name.toLowerCase().contains(q) ||
        (prod.sku?.toLowerCase().contains(q) ?? false) ||
        (prod.barcode?.toLowerCase().contains(q) ?? false);
  }).toList();
});
