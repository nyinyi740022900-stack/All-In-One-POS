import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cart.dart';
import 'held_sales_provider.dart';
import 'sales_providers.dart';

/// Clears every in-memory Sell-screen state that belongs to the shop the
/// device just switched away from — cart, held carts, search text and
/// category filter (audit QA-C2).
///
/// A branch switch swaps the local database file but none of these
/// providers are shop-scoped: a cart holding Shop A's products that
/// survives into Shop B either fails checkout with a confusing error or —
/// in an invoice-only shop, where checkout never looks products up —
/// commits sale rows referencing another shop's product ids.
/// Call right after the database reopens for the new shop.
void resetSellSessionState(Ref ref) {
  ref.read(cartProvider.notifier).clear();
  ref.read(heldSalesProvider.notifier).clearAll();
  ref.read(sellSearchProvider.notifier).state = '';
  ref.read(sellCategoryProvider.notifier).state = null;
}
