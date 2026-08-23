import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/search_debounce.dart';
import '../../data/local/database.dart';
import '../sell/sales_providers.dart';
import 'orders_repository.dart';

final ordersRepositoryProvider = Provider<OrdersRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final shopId = ref.watch(shopIdProvider);
  return OrdersRepository(db, shopId);
});

/// All non-deleted orders for the shop, newest-updated first. The Kanban board
/// groups these by [Order.status] client-side.
final ordersStreamProvider = StreamProvider<List<Order>>((ref) {
  return ref.watch(ordersRepositoryProvider).watchOrders();
});

/// Board search query (matches customer name, phone, or order number).
final orderSearchProvider = StateProvider<String>((ref) => '');

/// The query the board/list filters consume — settles [kSearchDebounce]
/// after typing pauses (audit H1). The text field and the "filters active"
/// clear button keep watching [orderSearchProvider] so they react on the
/// same keystroke.
final debouncedOrderSearchProvider =
    debouncedSearchProvider(orderSearchProvider);

/// Channel filter (`null` = all channels).
final orderChannelFilterProvider = StateProvider<String?>((ref) => null);

/// Payment-status filter (`null` = all).
final orderPaymentFilterProvider = StateProvider<String?>((ref) => null);

/// Status filter for the flat list (`null` = everything except cancelled —
/// cancelled orders stay reachable via an explicit filter tap rather than
/// cluttering the default view).
final orderStatusFilterProvider = StateProvider<String?>((ref) => null);

/// Previously-used carrier names for this shop, newest first, deduplicated —
/// backs the free-text carrier autocomplete so a shop doesn't have to
/// re-type "Grab" or a local courier's name every single order.
final carrierSuggestionsProvider = Provider<List<String>>((ref) {
  final all = ref.watch(ordersStreamProvider).valueOrNull ?? const [];
  final seen = <String>{};
  final out = <String>[];
  for (final o in all) {
    final c = o.deliveryCarrier;
    if (c != null && c.isNotEmpty && seen.add(c)) out.add(c);
  }
  return out;
});

/// True when any search/filter is narrowing the board (drives a clear button).
final ordersFilterActiveProvider = Provider<bool>((ref) {
  return ref.watch(orderSearchProvider).trim().isNotEmpty ||
      ref.watch(orderChannelFilterProvider) != null ||
      ref.watch(orderPaymentFilterProvider) != null;
});

/// Orders grouped by status, after applying the search + filters. Includes the
/// pipeline columns ([orderStatuses]) plus a `cancelled` bucket so cancelled
/// orders stay reachable (to restore or delete) instead of vanishing.
final ordersByStatusProvider = Provider<Map<String, List<Order>>>((ref) {
  final all = ref.watch(ordersStreamProvider).valueOrNull ?? const [];
  return groupOrdersForBoard(
    all,
    query: ref.watch(debouncedOrderSearchProvider),
    channel: ref.watch(orderChannelFilterProvider),
    payment: ref.watch(orderPaymentFilterProvider),
  );
});

/// Pure: filters [orders] by search/channel/payment and buckets them by status
/// (the pipeline columns plus `cancelled`). Kept side-effect-free so it can be
/// unit-tested without Riverpod. [query] matches customer name, phone, or
/// order number (case-insensitive).
Map<String, List<Order>> groupOrdersForBoard(
  List<Order> orders, {
  String query = '',
  String? channel,
  String? payment,
}) {
  final q = query.trim().toLowerCase();
  final map = {
    for (final s in orderStatuses) s: <Order>[],
    'cancelled': <Order>[],
  };
  for (final o in orders) {
    if (channel != null && o.channel != channel) continue;
    if (payment != null && o.paymentStatus != payment) continue;
    if (q.isNotEmpty) {
      final hay = '${o.customerName} ${o.customerPhone ?? ''} ${o.orderNo}'
          .toLowerCase();
      if (!hay.contains(q)) continue;
    }
    (map[o.status])?.add(o);
  }
  return map;
}

/// Search+channel+payment+status-filtered flat list for the Orders screen,
/// in [watchOrders]' order (newest-updated first). Replaced the old
/// side-scrolling Kanban board — with only two real statuses left (new,
/// delivered) a board added more chrome than it saved.
///
/// Deliberately watches [salesStreamProvider] (audit H1 re-check): the
/// search matches the INVOICE number of the sale an order was converted to
/// ([filterOrders.invoiceNoBySaleId]), and sales are an append-only ledger
/// that only ever grows — so this fires once per real sale event (already
/// transaction-batched by finalizeSale / sync), never per keystroke. It is
/// load-bearing, not a ripple leak.
final filteredOrdersListProvider = Provider<List<Order>>((ref) {
  final all = ref.watch(ordersStreamProvider).valueOrNull ?? const [];
  final sales = ref.watch(salesStreamProvider).valueOrNull ?? const [];
  return filterOrders(
    all,
    query: ref.watch(debouncedOrderSearchProvider),
    channel: ref.watch(orderChannelFilterProvider),
    payment: ref.watch(orderPaymentFilterProvider),
    status: ref.watch(orderStatusFilterProvider),
    invoiceNoBySaleId: {for (final s in sales) s.id: s.invoiceNo},
  );
});

/// Pure: filters [orders] by search/channel/payment/status. `status: null`
/// (the default) means "everything except cancelled" — cancelled orders
/// only show up once the shop explicitly filters for them. Kept
/// side-effect-free so it's unit-testable without Riverpod.
///
/// [invoiceNoBySaleId] lets the search also match the invoice number of the
/// sale an order was converted to — an order handed to a customer as a
/// printed/shared invoice (which shows the *order* number, generated before
/// conversion) later becomes a `Sales` row with its own, unrelated invoice
/// number, so a shop scanning/typing whichever number they have on hand
/// should find the order either way.
List<Order> filterOrders(
  List<Order> orders, {
  String query = '',
  String? channel,
  String? payment,
  String? status,
  Map<String, String> invoiceNoBySaleId = const {},
}) {
  final q = query.trim().toLowerCase();
  return orders.where((o) {
    if (status != null) {
      if (o.status != status) return false;
    } else if (o.status == 'cancelled') {
      return false;
    }
    if (channel != null && o.channel != channel) return false;
    if (payment != null && o.paymentStatus != payment) return false;
    if (q.isNotEmpty) {
      final invoiceNo =
          o.saleId != null ? (invoiceNoBySaleId[o.saleId] ?? '') : '';
      final hay =
          '${o.customerName} ${o.customerPhone ?? ''} ${o.orderNo} $invoiceNo'
              .toLowerCase();
      if (!hay.contains(q)) return false;
    }
    return true;
  }).toList();
}

/// Items for one order (for the detail / editor sheet).
final orderItemsProvider =
    FutureProvider.family<List<OrderItem>, String>((ref, orderId) async {
  return ref.watch(ordersRepositoryProvider).items(orderId);
});
