import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/database.dart';
import '../inventory/inventory_providers.dart';
import 'purchase_order_repository.dart';

final purchaseOrderRepositoryProvider = Provider<PurchaseOrderRepository>((ref) {
  return PurchaseOrderRepository(
    ref.watch(databaseProvider),
    ref.watch(shopIdProvider),
    ref.watch(inventoryRepositoryProvider),
  );
});

final purchaseOrdersProvider = StreamProvider<List<PurchaseOrder>>((ref) {
  return ref.watch(purchaseOrderRepositoryProvider).watchOrders();
});

final purchaseOrderItemsProvider =
    StreamProvider.family<List<PurchaseOrderItem>, String>((ref, poId) {
  return ref.watch(purchaseOrderRepositoryProvider).items(poId);
});
